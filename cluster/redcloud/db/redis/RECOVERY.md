# Redis AOF recovery

Use this procedure when the Redis pod exits with `Bad file format reading the append only file`.

The repair keeps the valid AOF prefix and discards the damaged tail. Do not start the repair until the complete Redis volume has been backed up.

## 1. Capture the live configuration

Run these commands with the cluster context that owns the `redis` namespace:

```sh
kubectl -n redis get pod -l app.kubernetes.io/instance=redis -o wide
kubectl -n redis get statefulset redis-master -o yaml > redis-master.statefulset.yaml
kubectl -n redis get helmrelease redis -o yaml > redis.helmrelease.live.yaml
kubectl -n redis describe pod -l app.kubernetes.io/instance=redis
```

Record the Redis image and the `master.persistence.path` from the StatefulSet. Do not assume the path is `/data`.

## 2. Stop Redis and back up the volume

Prevent repeated startup attempts while the files are being copied:

```sh
kubectl -n redis scale statefulset redis-master --replicas=0
kubectl -n redis wait --for=delete pod -l app.kubernetes.io/instance=redis --timeout=120s
```

On the NFS server, make a complete, metadata-preserving copy of the Redis directory. The configured source is `/mnt/share/k8s/redis-data-redis-master-0-pv` on `10.0.4.10`.

```sh
cp -a /mnt/share/k8s/redis-data-redis-master-0-pv \
  /mnt/share/k8s/redis-data-redis-master-0-pv.backup-$(date +%Y%m%d-%H%M%S)
```

Confirm the backup contains the AOF manifest, base RDB, and the original incremental AOF before proceeding. Keep the original files unchanged and retain the backup until Redis and its clients have been verified.

## 3. Run the checker with the PVC mounted

Use the exact Redis image recorded in step 1. Replace `<redis-image>` below, then apply this temporary pod:

```sh
kubectl -n redis apply -f - <<'EOF'
apiVersion: v1
kind: Pod
metadata:
  name: redis-aof-repair
spec:
  restartPolicy: Never
  securityContext:
    fsGroup: 1001
  containers:
    - name: redis
      image: <redis-image>
      command: ["/bin/sh", "-c", "sleep 3600"]
      volumeMounts:
        - name: redis-data
          mountPath: /data
  volumes:
    - name: redis-data
      persistentVolumeClaim:
        claimName: redis-static-pvc
EOF

kubectl -n redis wait --for=condition=Ready pod/redis-aof-repair --timeout=120s
kubectl -n redis exec redis-aof-repair -- sh -c 'command -v redis-check-aof'
```

Use the mounted path and the exact file named by the AOF manifest. For the incident in the logs, the expected file is `appendonlydir/appendonly.aof.105.incr.aof`:

```sh
kubectl -n redis exec redis-aof-repair -- \
  redis-check-aof --fix /data/appendonlydir/appendonly.aof.105.incr.aof
```

Record the reported valid length and discarded bytes. If the checker fails, stop and restore from the untouched backup; do not repeatedly modify the original AOF.

Remove the temporary pod after the repair:

```sh
kubectl -n redis delete pod redis-aof-repair --wait=true
```

## 4. Start and verify Redis

```sh
kubectl -n redis scale statefulset redis-master --replicas=1
kubectl -n redis rollout status statefulset/redis-master --timeout=180s
kubectl -n redis logs statefulset/redis-master --tail=200
```

The logs must show successful AOF loading and no `Bad file format` error. Verify authenticated access using the password from the existing `redis-auth` Secret without printing it in shell history:

```sh
kubectl -n redis exec statefulset/redis-master -- sh -c \
  'REDISCLI_AUTH="$(cat "$REDIS_PASSWORD_FILE")" redis-cli PING'

kubectl -n redis exec statefulset/redis-master -- \
  sh -c 'REDISCLI_AUTH="$(cat "$REDIS_PASSWORD_FILE")" redis-cli INFO persistence'
kubectl -n redis exec statefulset/redis-master -- \
  sh -c 'REDISCLI_AUTH="$(cat "$REDIS_PASSWORD_FILE")" redis-cli INFO keyspace'
```

Then confirm Immich and Nextcloud recover their Redis connections and remain Ready.

## 5. Roll back if startup still fails

Scale Redis down again, preserve the failed repaired directory, and restore the complete backup over the data directory on the NFS server. Start Redis only after the restore is complete. Do not delete the original backup until the rollback or repair has been independently verified.

## Configuration policy

The HelmRelease explicitly preserves the current Bitnami defaults:

```yaml
commonConfiguration: |-
  appendonly yes
  save ""
```

This means Redis uses AOF persistence and disables RDB snapshots. Any future change to this policy must be deliberate because the PVC is retained and contains persistent Redis state.

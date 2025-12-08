# Запуск шардированного решения:
```bash
docker compose up
```
Данные должны заполниться автоматически

## Типовые проблемы:
init_app может отдать
```error
MongoServerError: Time monotonicity violation: lookup time { forceReloadIncrement: 5, topologyTime: Timestamp(0, 1) } which is less than the earliest expected timeInStore { forceReloadIncrement: 5, topologyTime: Timestamp(1765215947, 32) }.
2025-12-08T17:51:05.110657221Z 
```
Это значит что кластер уже инициализирован и заполнен. Простой способ запустить все - compose down и удалить все вольюмы.

также init_app может вообще не запуститься:
```error
exec /scripts/init-cluster.sh: no such file or directory
```

Я потратил кучу времени и выдрал не буду говорить откуда кучу волос прежде чем понял что проблема в CRLF/LF. Убедитесь что строки оканчиваются LF.
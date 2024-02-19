# skyfly535_microservices
skyfly535 microservices repository

# HW19 Kubernetes. Networks, Storages.

## В процессе выполнения ДЗ выполнены следующие мероприятия:

1. Поднят кластер при помощи `terraform` в Yandex Cloud (подготовлен в прошлом ДЗ);

Регистрируем кластер в локальном окружении:

```
$ yc managed-kubernetes cluster get-credentials skyfly535 --external

Context 'yc-skyfly535' was added as default to kubeconfig '/home/roman/.kube/config'.
Check connection to cluster using 'kubectl cluster-info --kubeconfig /home/roman/.kube/config'.

Note, that authentication depends on 'yc' and its config profile 'terraform-profile'.
To access clusters using the Kubernetes API, please use Kubernetes Service Account.

$ kubectl cluster-info
Kubernetes control plane is running at https://158.160.98.118
CoreDNS is running at https://158.160.98.118/api/v1/namespaces/kube-system/services/kube-dns:dns/proxy
```

2. В сервисе `ui` настроен тип `LoadBalancer`  для работы с внешним облачным балансировщиком;

Тип LoadBalancer позволяет нам использовать внешний облачный балансировщик нагрузки как единую точку входа в наши сервисы, а не полагаться на IPTables и не открывать наружу весь кластер. Настроим соответствующим образом сервис ui, правим ui-service.yml:

```
apiVersion: v1
kind: Service
metadata:
  name: ui
  labels:
    app: reddit
    component: ui
spec:
  type: LoadBalancer
  ports:
  - port: 80
    protocol: TCP
    targetPort: 9292
  selector:
    app: reddit
    component: ui
```
3. Развернуто тестовое приложение при помощи манифестов из прошлого ДЗ с `LoadBalancer`;

```
$ kubectl apply -f kubernetes/reddit/dev-namespace.yml
namespace/dev created

$ kubectl get pods -n dev
NAME                       READY   STATUS    RESTARTS   AGE
comment-56cbfb5bdc-5prjp   1/1     Running   0          83s
comment-56cbfb5bdc-cd8sb   1/1     Running   0          83s
comment-56cbfb5bdc-dbxjd   1/1     Running   0          83s
mongo-7f764c4b5b-rjqz4     1/1     Running   0          81s
post-6848446659-8dbvt      1/1     Running   0          80s
post-6848446659-ctm8h      1/1     Running   0          80s
post-6848446659-kzvz2      1/1     Running   0          80s
ui-59446c685-44q8m         1/1     Running   0          79s
ui-59446c685-94fl7         1/1     Running   0          79s
ui-59446c685-bmsr5         1/1     Running   0          79s

$ kubectl get services -n dev
NAME         TYPE           CLUSTER-IP      EXTERNAL-IP      PORT(S)        AGE
comment      ClusterIP      10.96.144.60    <none>           9292/TCP       89s
comment-db   ClusterIP      10.96.240.222   <none>           27017/TCP      90s
mongodb      ClusterIP      10.96.159.155   <none>           27017/TCP      88s
post         ClusterIP      10.96.130.221   <none>           5000/TCP       86s
post-db      ClusterIP      10.96.170.147   <none>           27017/TCP      87s
ui           LoadBalancer   10.96.251.81    158.160.139.68   80:31833/TCP   85s

$ kubectl get service -n dev --selector component=ui
NAME   TYPE           CLUSTER-IP      EXTERNAL-IP      PORT(S)        AGE
ui     LoadBalancer   10.96.239.248   158.160.147.33   80:30286/TCP   7m16s
```

Проверим в браузере: `http://158.160.147.33`

Видим, что все поды поднялись, сервисы работают, а у сервиса LoadBalancer появился внешний адрес. По этому адресу и доступно наше приложение.

Балансировка с помощью Service типа  `LoadBalancer` имеет ряд недостатков:

- Нельзя управлять с помощью http URI (L7-балансировщика)
- Используются только облачные балансировщики
- Нет гибких правил работы с трафиком

Для более удобного управления входящим снаружи трафиком и решения недостатков LoadBalancer можно использовать другой объект Kubernetes - `Ingress`.

4. Запущен `Ingress Controller` на базе балансировщика `Nginx`;

Ingress - это набор правил внутри кластера Kuberntes, предназначенных для того, чтобы входящие подключения могли достичь сервисов. Сами по себе Ingress'ы это просто правила. Для их применения нужен Ingress Controller.

Ingress Controller - это скорее плагин (а значит и отдельный POD), который состоит из 2-х функциональных частей:

- Приложение, которое отслеживает через k8s API новые объекты Ingress и обновляет конфигурацию балансировщика
- Балансировщик (Nginx, haproxy, traefik, ...), который и занимается управлением сетевым трафиком

Установка ingress controller:

```
kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.2/deploy/static/provider/cloud/deploy.yaml
```

Основные задачи, решаемые с помощью Ingress'ов:

- Организация единой точки входа в приложения снаружи
- Обеспечение балансировки трафика
- Терминация SSL
- Виртуальный хостинг на основе имен

5. Создан и применен манифест `ingress` для сервиса `ui`;

```
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: ui
spec:
  rules:
  - http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: ui
            port:
              number: 9292
```
Изменяем, применяем:

```
$ kubectl apply -n dev -f ui-service.yml
service/ui configured

$ kubectl apply -n dev -f ui-ingress.yml
ingress.networking.k8s.io/ui created
```
Смотрим статус:

```
$ kubectl get ingress ui -n dev
NAME   CLASS    HOSTS   ADDRESS          PORTS   AGE
ui     nginx   *       158.160.148.14   80      16m
```
6. Создан TLS сертификат, на его основе создан `Secret`;

Сгенерирован сертификат:

```
$ openssl req -x509 -nodes -days 365 -newkey rsa:2048 -keyout tls.key -out tls.crt -subj "/CN=158.160.148.14"
Generating a RSA private key
..+++++
...............................................................+++++
writing new private key to 'tls.key'
-----
Создан секрет с данным сертификатом:

```

```
$ kubectl create secret tls ui-ingress --key tls.key --cert tls.crt -n dev
secret/ui-ingress created

$ kubectl describe secret ui-ingress -n dev
Name:         ui-ingress
Namespace:    dev
Labels:       <none>
Annotations:  <none>

Type:  kubernetes.io/tls

Data
====
tls.crt:  1127 bytes
tls.key:  1704 bytes
```

7. Настроен доступ к тестовому приложению по `https` (с самоподписным сертификатом);

Обновлен манифест `ui-ingress.yml`:

```
apiVersion: networking.k8s.io/v1
kind: Ingress
metadata:
  name: ui
  annotations:
    nginx.ingress.kubernetes.io/force-ssl-redirect: "true"
spec:
  ingressClassName: nginx
  tls:
  - secretName: ui-ingress
  rules:
  - http:
      paths:
      - path: /
        pathType: Prefix
        backend:
          service:
            name: ui
            port:
              number: 9292
```

Запускаем:

```
$ kubectl apply -n dev -f ui-ingress.yml
ingress.networking.k8s.io/ui configured
```
Проверяем:

```
$ kubectl get ingress ui -n dev
NAME   CLASS   HOSTS   ADDRESS          PORTS     AGE
ui     nginx   *       158.160.148.14   80, 443   2m39s

$ kubectl describe ingress ui -n dev
Name:             ui
Labels:           <none>
Namespace:        dev
Address:          158.160.148.14
Ingress Class:    nginx
Default backend:  <default>
TLS:
  ui-ingress terminates
Rules:
  Host        Path  Backends
  ----        ----  --------
  *
              /   ui:9292 (10.112.128.15:9292,10.112.129.8:9292,10.112.129.9:9292)
Annotations:  nginx.ingress.kubernetes.io/force-ssl-redirect: true
Events:
  Type    Reason  Age                    From                      Message
  ----    ------  ----                   ----                      -------
  Normal  Sync    2m16s (x2 over 2m54s)  nginx-ingress-controller  Scheduled for sync
```
![Alt text](redit_ssl.jpg)

## Дополнительные задания

8. Создаваемый объект `Secret` в виде Kubernetes-манифеста;

Выведено содержание созданного секрета:

```
cat kubernetes/reddit/ui-sec-ingress.yml
```
Вывод команды сохранен в файл `cat ./kubernetes/reddit/ui-sec-ingress.yml`.

9. Ограничен любой трафик, поступающий на `mongodb`, кроме сервисов `post` и `comment`;

В прошлых проектах мы договорились о том, что хотелось бы разнести сервисы базы данных и сервис фронтенда по разным сетям, сделав их недоступными друг для друга. В Kubernetes у нас так сделать не получится с помощью отдельных сетей, так как все POD-ы могут достучаться друг до друга по-умолчанию. Мы будем использовать `NetworkPolicy` - инструмент для декларативного описания потоков трафика.

Описываем правило в манифесте `mongo-network-policy.yml`. Применяем:

```
$ kubectl apply -n dev -f mongo-network-policy.yml
networkpolicy.networking.k8s.io/deny-db-traffic created
```
Проверяем;

```
$ kubectl get networkpolicy -n dev
NAME              POD-SELECTOR                 AGE
deny-db-traffic   app=reddit,component=mongo   47m

$ kubectl describe networkpolicy -n dev
Name:         deny-db-traffic
Namespace:    dev
Created on:   2024-02-18 16:41:40 +1000 +10
Labels:       app=reddit
Annotations:  <none>
Spec:
  PodSelector:     app=reddit,component=mongo
  Allowing ingress traffic:
    To Port: <any> (traffic allowed to all ports)
    From:
      PodSelector: app=reddit,component=comment
    From:
      PodSelector: app=reddit,component=post
  Not affecting egress traffic
  Policy Types: Ingress
```
10. Создано постоянное хранилище данных для `mongodb` при помощи `PersistentVolume`;

Основной Stateful сервис в нашем приложении - это базы данных MongoDB. В текущий момент она запускается в виде Deployment и хранит данные в стандартных Docker Volume-ах. Это имеет несколько проблем:

При удалении POD-а удаляется и Volume
Потерям Nod'ы с mongo грозит потерей данных
Запуск базы на другой ноде запускает новый экземпляр данных
Пробуем удалить deployment для mongo и создать его заново. После запуска пода база оказывается пустой.

Для постоянного хранения данных используется PersistentVolume.

Создадим диск в облаке:

```
$ yc compute disk create --zone ru-central1-a --name k8s --size 4 --description "disk for k8s"
done (5s)
id: fhmahkjc83c8ucpbk6em
folder_id: b1ghhcttrug793gc11tt
created_at: "2024-02-18T07:42:05Z"
name: k8s
description: disk for k8s
type_id: network-hdd
zone_id: ru-central1-a
size: "4294967296"
block_size: "4096"
status: READY
disk_placement_policy: {}
```
Описываем в манифесте ` mongo-volume.yml PersitentVolume`

```
apiVersion: v1
kind: PersistentVolume
metadata:
  name: mongo-pv
spec:
  capacity:
    storage: 4Gi
  accessModes:
    - ReadWriteOnce
  csi:
    driver: disk-csi-driver.mks.ycloud.io
    fsType: ext4
    volumeHandle: fhmahkjc83c8ucpbk6em <--- берем из вывода предыдущей команды
```

Мы создали ресурс дискового хранилища, распространенный на весь кластер, в виде PersistentVolume. Чтобы выделить приложению часть такого ресурса - нужно создать запрос на выдачу - PersistentVolumeClain. Claim - это именно запрос, а не само хранилище. С помощью запроса можно выделить место как из конкретного PersistentVolume (тогда параметры accessModes и StorageClass должны соответствовать, а места должно хватать), так и просто создать отдельный PersistentVolume под конкретный запрос.

Описываем `mongo-claim.yml`:

```
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: mongo-pvc
spec:
  storageClassName: ""
  accessModes:
    - ReadWriteOnce
  resources:
    requests:
      storage: 4Gi
  volumeName: mongo-pv
```

Обновляем `mongo-deployment.yml`:

```
volumes:
       - name: mongo-persistent-storage
         emptyDir: {}    <----- меняем на следующие строки
+        persistentVolumeClaim:
+          claimName: mongo-pvc
```
Применяем:

```
$ kubectl apply -f mongo-volume.yml
persistentvolume/mongo-pv created

$ kubectl apply -f mongo-claim.yml -n dev
persistentvolumeclaim/mongo-pvc created

$ kubectl apply -f mongo-deployment.yml -n dev
deployment.apps/mongo configured
```

Проверяем:

```
$ kubectl get pv
NAME       CAPACITY   ACCESS MODES   RECLAIM POLICY   STATUS      CLAIM   STORAGECLASS   REASON   AGE
mongo-pv   4Gi        RWO            Retain           Available                                   59s

$ kubectl describe pv mongo-pv
Name:            mongo-pv
Labels:          <none>
Annotations:     <none>
Finalizers:      [kubernetes.io/pv-protection]
StorageClass:
Status:          Available
Claim:
Reclaim Policy:  Retain
Access Modes:    RWO
VolumeMode:      Filesystem
Capacity:        4Gi
Node Affinity:   <none>
Message:
Source:
    Type:              CSI (a Container Storage Interface (CSI) volume source)
    Driver:            disk-csi-driver.mks.ycloud.io
    FSType:            ext4
    VolumeHandle:      fhmahkjc83c8ucpbk6em
    ReadOnly:          false
    VolumeAttributes:  <none>
Events:                <none>

$ kubectl get pvc -n dev
NAME        STATUS    VOLUME                CAPACITY   ACCESS MODES   STORAGECLASS   AGE
mongo-pvc   Pending   mongo-ya-pd-storage   0                                        74s
```
Ждем около 10 минут

```
$ kubectl get pods -n dev
NAME                       READY   STATUS    RESTARTS   AGE
comment-56cbfb5bdc-l5c84   1/1     Running   0          102m
comment-56cbfb5bdc-ng22h   1/1     Running   0          102m
comment-56cbfb5bdc-x6trv   1/1     Running   0          102m
mongo-794976987-j4wwk      0/1     Pending   0          5m26s <---- Ждем!
mongo-7f764c4b5b-hfkwm     1/1     Running   0          102m
post-6848446659-ndlmm      1/1     Running   0          102m
post-6848446659-v7gql      1/1     Running   0          102m
post-6848446659-vvsv5      1/1     Running   0          102m
ui-65846d4847-s4ssd        1/1     Running   0          102m
ui-65846d4847-s62qk        1/1     Running   0          102m
ui-65846d4847-wlx5c        1/1     Running   0          102m
```
Проверяем создание поста с последующим удалением и созданием деплоя mongo. Пост остался на месте.

For more information see: [полезное чтиво](https://habr.com/ru/companies/T1Holding/articles/781368/)

# HW18 Kubernetes. Запуск кластера и приложения. Модель безопасности.

## В процессе выполнения ДЗ выполнены следующие мероприятия:

1. Подготовлено локальное окружение для работы с Kubernetes:

- kubectl - главная утилита для работы с Kubernets API (все, что делает kubectl, можно сделать с помощью HTTP-запросов к API k8s)

- minikube - утилита для разворачивания локальной инсталляции Kubernetes

- ~/.kube - каталог, который содержит служебную информацию для kubectl (конфиги, кеши, схемы API);

2. Поднят кластер в `minikube`;

Стандартный драйвер для развертывания кластера в minikube docker. В данной конфигурации кластера у меня возникли проблемы с доступом к образам моего аккаунта в `Docker Hub`, поэтому кластер был поднят с драйвером `Virtualbox` (с ним проблем не было).

```
 minikube start --driver=virtualbox
```
В процессе поднятия кластера автоматически настраивается `kubectl`.

```
$ kubectl get nodes
NAME       STATUS   ROLES           AGE   VERSION
minikube   Ready    control-plane   32s   v1.28.3
```
3. Приведены в соответствие подготовленые на прошлом ДЗ манифесты `ui-deployment.yml`, `component-deployment.yml`, `post-deployment.yml`, `mongo-deployment.yml` (каталог `./kubernetes/reddit`) для развертывания тестового приложения;

4. Развернута инфраструктура из подготовленных манифестов;

Можно разворачивать по отдельности

```
kubectl apply -f ui-deployment.yml

kubectl apply -f component-deployment.yml

kubectl apply -f post-deployment.yml

kubectl apply -f mongo-deployment.yml
```
Можно все сразу

```
kubectl apply -f kubernetes/reddit
```

Проверяем:

```
$  kubectl get pods
NAME                       READY   STATUS    RESTARTS   AGE
comment-698585b76f-48nbc   1/1     Running   0          116s
comment-698585b76f-8pgqf   1/1     Running   0          116s
comment-698585b76f-qr8v2   1/1     Running   0          116s
mongo-64c9bf74db-hbj9n     1/1     Running   0          116s
post-6b48846c57-8hkjs      1/1     Running   0          116s
post-6b48846c57-gtxfs      1/1     Running   0          116s
post-6b48846c57-pfzh7      1/1     Running   0          116s
ui-676bf545dc-6496k        1/1     Running   0          116s
ui-676bf545dc-7np2q        1/1     Running   0          116s
ui-676bf545dc-tqfps        1/1     Running   0          116s

$ kubectl get deployment
NAME      READY   UP-TO-DATE   AVAILABLE   AGE
comment   3/3     3            3           2m35s
mongo     1/1     1            1           2m35s
post      3/3     3            3           2m35s
ui        3/3     3            3           2m35s
```
Можно пробросить порт пода на локальную машину:

```
kubectl port-forward ui-676bf545dc-6496k 8080:9292
Forwarding from 127.0.0.1:8080 -> 9292
Forwarding from [::1]:8080 -> 9292
```
Проверяем в браузере по адресу `http://127.0.0.1:8080/`

5. Подготовлены манифесты `Service` для связи компонентов между собой и с внешним миром;

Service - абстракция, которая определяет набор POD-ов (Endpoints) и способ доступа к ним.

Созданы следующие манифесты `comment-service.yml`, `post-service.yml`, `mongodb-service.yml`, `comment-mongodb-service.yml`, `post-mongodb-service.yml` (каталог `./kubernetes/reddit`).

```
$ kubectl get services
NAME         TYPE        CLUSTER-IP       EXTERNAL-IP   PORT(S)          AGE
comment      ClusterIP   10.105.43.64     <none>        9292/TCP         13m
comment-db   ClusterIP   10.108.160.146   <none>        27017/TCP        13m
kubernetes   ClusterIP   10.96.0.1        <none>        443/TCP          26m
mongodb      ClusterIP   10.102.121.56    <none>        27017/TCP        13m
post         ClusterIP   10.107.58.225    <none>        5000/TCP         13m
post-db      ClusterIP   10.111.128.9     <none>        27017/TCP        13m
ui           NodePort    10.100.170.152   <none>        9292:31702/TCP   13m
```

6. Переназначены переменные окружения, указывающие на сервис `comment_db` в deployment сервисов `ui`, `comment`;

Если пробросить порт сервиса ui наружу, попытаться подключиться к нему, то мы увидим ошибку. Сервис ui ищет совсем другой адрес: comment_db, а не mongodb, как и сервис comment ищет post_db. Эти адреса заданы в их `Dockerfile` в виде переменных окружения: `POST_DATABASE_HOST=post_db` и `COMMENT_DATABASE_HOST=comment_db`.

```
comment-deployment.yml

containers:
- image: skyfly534/comment
  name: comment
  env:
  - name: COMMENT_DATABASE_HOST
    value: mongodb
```

```
post-deployment.yml

containers:
- image: r2d2k/post
  name: post
  env:
  - name: POST_DATABASE_HOST
    value: mongodb
```

Пересобираем

```
kubectl apply -f kubernetes/reddit
```

Пробрасываем порт

```
kubectl port-forward ui-676bf545dc-6496k 8080:9292
```
Идем в браузер `http://127.0.0.1:8080`. Все работает. Пишем посты, сохраняем их.

7. Написан `Service` для `ui` (`ui-service.yml`) для обеспечения доступа к ui снаружи;

```
$ minikube service ui
|-----------|------|-------------|-----------------------------|
| NAMESPACE | NAME | TARGET PORT |             URL             |
|-----------|------|-------------|-----------------------------|
| default   | ui   |        9292 | http://192.168.59.101:31702 |
|-----------|------|-------------|-----------------------------|
🎉  Opening service default/ui in default browser...
roman@root-ubuntu:~/DevOps/skyfly535_microservices$ Found ffmpeg: /opt/yandex/browser-beta/libffmpeg.so
	avcodec: 3876708
	avformat: 3874148
	avutil: 3743332
Ffmpeg version is OK! Let's use it.
[43557:43557:0214/193723.242300:ERROR:variations_seed_processor.cc(253)] Trial from abt study=BREXP-6200 already created
[43557:43557:0214/193723.242607:ERROR:variations_seed_processor.cc(253)] Trial from abt study=Spaces already created
[43557:43557:0214/193723.583001:ERROR:isolated_origin_util.cc(74)] Ignoring port number in isolated origin: chrome://custo
Окно или вкладка откроются в текущем сеансе браузера.
```

```
$ minikube service list
|-------------|------------|--------------|-----------------------------|
|  NAMESPACE  |    NAME    | TARGET PORT  |             URL             |
|-------------|------------|--------------|-----------------------------|
| default     | comment    | No node port |                             |
| default     | comment-db | No node port |                             |
| default     | kubernetes | No node port |                             |
| default     | mongodb    | No node port |                             |
| default     | post       | No node port |                             |
| default     | post-db    | No node port |                             |
| default     | ui         |         9292 | http://192.168.59.101:31702 |
| kube-system | kube-dns   | No node port |                             |
|-------------|------------|--------------|-----------------------------|
```

В комплекте с minikube идёт достаточно большое количество дополнений:

```
$ minikube addons list
|-----------------------------|----------|--------------|--------------------------------|
|         ADDON NAME          | PROFILE  |    STATUS    |           MAINTAINER           |
|-----------------------------|----------|--------------|--------------------------------|
| ambassador                  | minikube | disabled     | 3rd party (Ambassador)         |
| auto-pause                  | minikube | disabled     | minikube                       |
| cloud-spanner               | minikube | disabled     | Google                         |
| csi-hostpath-driver         | minikube | disabled     | Kubernetes                     |
| dashboard                   | minikube | disabled     | Kubernetes                     |
| default-storageclass        | minikube | enabled ✅   | Kubernetes                     |
| efk                         | minikube | disabled     | 3rd party (Elastic)            |
| freshpod                    | minikube | disabled     | Google                         |
| gcp-auth                    | minikube | disabled     | Google                         |
| gvisor                      | minikube | disabled     | minikube                       |
| headlamp                    | minikube | disabled     | 3rd party (kinvolk.io)         |
| helm-tiller                 | minikube | disabled     | 3rd party (Helm)               |
| inaccel                     | minikube | disabled     | 3rd party (InAccel             |
|                             |          |              | [info@inaccel.com])            |
| ingress                     | minikube | disabled     | Kubernetes                     |
| ingress-dns                 | minikube | disabled     | minikube                       |
| inspektor-gadget            | minikube | disabled     | 3rd party                      |
|                             |          |              | (inspektor-gadget.io)          |
| istio                       | minikube | disabled     | 3rd party (Istio)              |
| istio-provisioner           | minikube | disabled     | 3rd party (Istio)              |
| kong                        | minikube | disabled     | 3rd party (Kong HQ)            |
| kubeflow                    | minikube | disabled     | 3rd party                      |
| kubevirt                    | minikube | disabled     | 3rd party (KubeVirt)           |
| logviewer                   | minikube | disabled     | 3rd party (unknown)            |
| metallb                     | minikube | disabled     | 3rd party (MetalLB)            |
| metrics-server              | minikube | disabled     | Kubernetes                     |
| nvidia-device-plugin        | minikube | disabled     | 3rd party (NVIDIA)             |
| nvidia-driver-installer     | minikube | disabled     | 3rd party (Nvidia)             |
| nvidia-gpu-device-plugin    | minikube | disabled     | 3rd party (Nvidia)             |
| olm                         | minikube | disabled     | 3rd party (Operator Framework) |
| pod-security-policy         | minikube | disabled     | 3rd party (unknown)            |
| portainer                   | minikube | disabled     | 3rd party (Portainer.io)       |
| registry                    | minikube | disabled     | minikube                       |
| registry-aliases            | minikube | disabled     | 3rd party (unknown)            |
| registry-creds              | minikube | disabled     | 3rd party (UPMC Enterprises)   |
| storage-provisioner         | minikube | enabled ✅   | minikube                       |
| storage-provisioner-gluster | minikube | disabled     | 3rd party (Gluster)            |
| storage-provisioner-rancher | minikube | disabled     | 3rd party (Rancher)            |
| volumesnapshots             | minikube | disabled     | Kubernetes                     |
|-----------------------------|----------|--------------|--------------------------------|
```
8. Запущен `dashboard` для отслеживания состояния и управления кластером;

```
$ minikube dashboard
🔌  Enabling dashboard ...
    ▪ Используется образ docker.io/kubernetesui/dashboard:v2.7.0
    ▪ Используется образ docker.io/kubernetesui/metrics-scraper:v1.0.8
💡  Some dashboard features require the metrics-server addon. To enable all features please run:

	minikube addons enable metrics-server


🤔  Verifying dashboard health ...
🚀  Launching proxy ...
🤔  Verifying proxy health ...
🎉  Opening http://127.0.0.1:36359/api/v1/namespaces/kubernetes-dashboard/services/http:kubernetes-dashboard:/proxy/ in your default browser...
Found ffmpeg: /opt/yandex/browser-beta/libffmpeg.so
	avcodec: 3876708
	avformat: 3874148
	avutil: 3743332
Ffmpeg version is OK! Let's use it.
[45337:45337:0214/195604.197044:ERROR:variations_seed_processor.cc(253)] Trial from abt study=BREXP-6200 already created
[45337:45337:0214/195604.197256:ERROR:variations_seed_processor.cc(253)] Trial from abt study=Spaces already created
[45337:45337:0214/195604.461036:ERROR:isolated_origin_util.cc(74)] Ignoring port number in isolated origin: chrome://custo
Окно или вкладка откроются в текущем сеансе браузера.
```

После активации dashboard она откроется в браузере. Можно посмотреть состояние кластера со всех сторон:

- Отслеживать состояние кластера и рабочих нагрузок в нём;

- Создавать новые объекты (загружать YAML-файлы);

- Удалять и изменять объекты (кол-во реплик, YAML-файлы);

- Отслеживать логи в POD-ах;

- При включении Heapster-аддона смотреть нагрузку на POD-ах.

9. Подготовлен манифест `dev-namespace.yml` для отделения среды разработки тестового приложения от всего остального;

Для того, чтобы выбрать конкретное пространство имен, нужно указать флаг `-n` или `–namespace` при запуске kubectl.

Проверяем имеющиеся у нас в кластере

```
$ kubectl get all -n kube-system
NAME                                   READY   STATUS    RESTARTS   AGE
pod/coredns-5dd5756b68-lb2wk           1/1     Running   0          52m
pod/etcd-minikube                      1/1     Running   0          53m
pod/kube-apiserver-minikube            1/1     Running   0          53m
pod/kube-controller-manager-minikube   1/1     Running   0          53m
pod/kube-proxy-bbfqc                   1/1     Running   0          52m
pod/kube-scheduler-minikube            1/1     Running   0          53m
pod/storage-provisioner                1/1     Running   0          53m

NAME               TYPE        CLUSTER-IP   EXTERNAL-IP   PORT(S)                  AGE
service/kube-dns   ClusterIP   10.96.0.10   <none>        53/UDP,53/TCP,9153/TCP   53m

NAME                        DESIRED   CURRENT   READY   UP-TO-DATE   AVAILABLE   NODE SELECTOR            AGE
daemonset.apps/kube-proxy   1         1         1       1            1           kubernetes.io/os=linux   53m

NAME                      READY   UP-TO-DATE   AVAILABLE   AGE
deployment.apps/coredns   1/1     1            1           53m

NAME                                 DESIRED   CURRENT   READY   AGE
replicaset.apps/coredns-5dd5756b68   1         1         1       53m
```

При старте Kubernetes кластер имеет 3 namespace:

- default - для объектов для которых не определен другой Namespace (в нём мы работали все это время)
- kube-system - для объектов созданных Kubernetes и для управления им
- kube-public - для объектов к которым нужен доступ из любой точки кластера

Для того, чтобы выбрать конкретное пространство имен, нужно указать флаг `-n` или `–namespace` при запуске kubectl.

```
apiVersion: v1
kind: Namespace
metadata:
  name: dev
```
Применим изменения

```
$ kubectl apply -f dev-namespace.yml
namespace/dev created

$ kubectl apply -n dev -f kubernetes/reddit/
```
10. Создан Kubernetes кластер под названием `skyfly535` через веб-интерфейс консоли `Yandex Cloud` (`Managed Service for kubernetes`);

- Идём в Yandex Cloud, перейдите в "Managed Service for kubernetes"

- Жмём "Создать Cluster"

- Имя кластера может быть произвольным

- Если нет сервис аккаунта его можно создать

- Релизный канал *** Rapid ***

- Версия k8s 1.25

- Зона доступности - на ваше усмотрение (сети - аналогично)

- Жмём "Создать"" и ждём, пока поднимется кластер

После создания кластера, вам нужно создать группу узлов, входящих в кластер

- Версия k8s 1.25

- Количество узлов - 2

- vCPU - 4

- RAM - 8

- Disk - SSD 96ГБ (минимальное значение)

- В поле "Доступ" добавьте свой логин и публичный ssh-ключ

После поднятия кластера настраиваем к нему доступ:

```
$ yc managed-kubernetes cluster get-credentials skyfly535 --external

Context 'yc-skyfly535' was added as default to kubeconfig '/home/roman/.kube/config'.
Check connection to cluster using 'kubectl cluster-info --kubeconfig /home/roman/.kube/config'.

Note, that authentication depends on 'yc' and its config profile 'terraform-profile'.
To access clusters using the Kubernetes API, please use Kubernetes Service Account.

$ kubectl config get-contexts
CURRENT   NAME           CLUSTER                               AUTHINFO                              NAMESPACE
          yc-skyfly      yc-managed-k8s-cat2ru389rf94j781as5   yc-managed-k8s-cat2ru389rf94j781as5
          yc-skyfly534   yc-managed-k8s-cat895hbh2845cqv67tb   yc-managed-k8s-cat895hbh2845cqv67tb
*         yc-skyfly535   yc-managed-k8s-catcovvk572g06lr0tqj   yc-managed-k8s-catcovvk572g06lr0tqj
```
вводим команду из выхлопа команды `yc managed-kubernetes cluster get-credentials skyfly535 --external`
```
$ kubectl cluster-info --kubeconfig /home/roman/.kube/config
Kubernetes control plane is running at https://178.154.205.197
CoreDNS is running at https://178.154.205.197/api/v1/namespaces/kube-system/services/kube-dns:dns/proxy

To further debug and diagnose cluster problems, use 'kubectl cluster-info dump'.
```

11. Запущено тестовое приложение в кластере YC;

```
$ kubectl apply -f kubernetes/reddit/dev-namespace.yml
namespace/dev created

$ kubectl apply -n dev -f kubernetes/reddit/
deployment.apps/comment created
service/comment-db created
service/comment created
namespace/dev unchanged
deployment.apps/mongo created
service/mongodb created
deployment.apps/post created
service/post-db created
service/post created
deployment.apps/ui created
service/ui created

$ kubectl get services -n dev
NAME         TYPE        CLUSTER-IP      EXTERNAL-IP   PORT(S)          AGE
comment      ClusterIP   10.96.245.190   <none>        9292/TCP         39s
comment-db   ClusterIP   10.96.207.56    <none>        27017/TCP        40s
mongodb      ClusterIP   10.96.208.88    <none>        27017/TCP        37s
post         ClusterIP   10.96.211.182   <none>        5000/TCP         36s
post-db      ClusterIP   10.96.245.177   <none>        27017/TCP        36s
ui           NodePort    10.96.152.96    <none>        9292:31758/TCP   35s

$ kubectl get pods -n dev
NAME                       READY   STATUS    RESTARTS   AGE
comment-56cbfb5bdc-gftjr   1/1     Running   0          54s
comment-56cbfb5bdc-j2dnw   1/1     Running   0          54s
comment-56cbfb5bdc-n8sqb   1/1     Running   0          54s
mongo-7f764c4b5b-6h78x     1/1     Running   0          52s
post-6848446659-8786l      1/1     Running   0          51s
post-6848446659-8pnkl      1/1     Running   0          51s
post-6848446659-phrg7      1/1     Running   0          51s
ui-59446c685-64ttz         1/1     Running   0          49s
ui-59446c685-dmkdt         1/1     Running   0          49s
ui-59446c685-fbng5         1/1     Running   0          49s

$ kubectl get nodes -o wide
NAME                        STATUS   ROLES    AGE   VERSION   INTERNAL-IP   EXTERNAL-IP       OS-IMAGE             KERNEL-VERSION      CONTAINER-RUNTIME
cl1rb9rs892oqjsut8v4-iwuj   Ready    <none>   92m   v1.25.4   10.128.0.15   178.154.205.124   Ubuntu 20.04.6 LTS   5.4.0-167-generic   containerd://1.6.22
cl1v5h010ohkknr8cbbs-ehot   Ready    <none>   92m   v1.25.4   10.128.0.23   158.160.107.18    Ubuntu 20.04.6 LTS   5.4.0-167-generic   containerd://1.6.22
```
Идем в браузер `http://178.154.205.124:31758/`, проверяем. Все работает.

12. Развернут Kubernetes-кластер в YC с помощью `Terraform`;

Нагуглена конфигурация Terraform для развертывания Kubernetes кластера с использованием ресурсов `yandex_kubernetes_cluster` и `yandex_kubernetes_node_group` (каталог `./kubernetes/terraform_YC_k8s`).

```
$ kubectl cluster-info
Kubernetes control plane is running at https://178.154.205.197
CoreDNS is running at https://178.154.205.197/api/v1/namespaces/kube-system/services/kube-dns:dns/proxy

To further debug and diagnose cluster problems, use 'kubectl cluster-info dump'.
```
13. Создан `YAML-манифесты` для описания созданных сущностей для включения `dashboard`;

Для установки dashboard воспользуемся стандартным манифестом со страницы разработчика (https://kubernetes.io/docs/tasks/access-application-cluster/web-ui-dashboard/).
Сохраним манифест в каталог kubernetes/dashboard.

```
$ wget https://raw.githubusercontent.com/kubernetes/dashboard/v2.7.0/aio/deploy/recommended.yaml
```

Для того, чтобы полноценно управлять кластером, нужно создать пользователя с ролью `cluster-admin`. Подготовим манифесты `admin-account.yaml` `admin-roleBinding.yaml` и сохраним их рядом с манифестом dashboard.

Применяем

```
kubectl apply -f dashboard/
serviceaccount/admin-user created
clusterrolebinding.rbac.authorization.k8s.io/admin-user unchanged
namespace/kubernetes-dashboard unchanged
serviceaccount/kubernetes-dashboard unchanged
service/kubernetes-dashboard unchanged
secret/kubernetes-dashboard-certs unchanged
secret/kubernetes-dashboard-csrf configured
Warning: resource secrets/kubernetes-dashboard-key-holder is missing the kubectl.kubernetes.io/last-applied-configuration annotation which is required by kubectl apply. kubectl apply should only be used on resources created declaratively by either kubectl create --save-config or kubectl apply. The missing annotation will be patched automatically.
secret/kubernetes-dashboard-key-holder configured
configmap/kubernetes-dashboard-settings unchanged
role.rbac.authorization.k8s.io/kubernetes-dashboard unchanged
clusterrole.rbac.authorization.k8s.io/kubernetes-dashboard unchanged
rolebinding.rbac.authorization.k8s.io/kubernetes-dashboard unchanged
clusterrolebinding.rbac.authorization.k8s.io/kubernetes-dashboard unchanged
deployment.apps/kubernetes-dashboard unchanged
service/dashboard-metrics-scraper unchanged
deployment.apps/dashboard-metrics-scraper unchanged

$ kubectl get pods --all-namespaces
NAMESPACE              NAME                                                  READY   STATUS    RESTARTS       AGE
dev                    comment-56cbfb5bdc-gftjr                              1/1     Running   0              22m
dev                    comment-56cbfb5bdc-j2dnw                              1/1     Running   0              22m
dev                    comment-56cbfb5bdc-n8sqb                              1/1     Running   0              22m
dev                    mongo-7f764c4b5b-6h78x                                1/1     Running   0              22m
dev                    post-6848446659-8786l                                 1/1     Running   0              22m
dev                    post-6848446659-8pnkl                                 1/1     Running   0              22m
dev                    post-6848446659-phrg7                                 1/1     Running   0              22m
dev                    ui-59446c685-64ttz                                    1/1     Running   0              21m
dev                    ui-59446c685-dmkdt                                    1/1     Running   0              21m
dev                    ui-59446c685-fbng5                                    1/1     Running   0              21m
kube-system            calico-node-l4lzt                                     1/1     Running   0              112m
kube-system            calico-node-ndh9j                                     1/1     Running   0              113m
kube-system            calico-typha-7dc6645875-659s7                         1/1     Running   0              111m
kube-system            calico-typha-horizontal-autoscaler-785c94fb55-tr4zn   1/1     Running   0              115m
kube-system            calico-typha-vertical-autoscaler-7679879786-qb2ck     1/1     Running   3 (112m ago)   115m
kube-system            coredns-5c5df59fd4-jlqbh                              1/1     Running   0              115m
kube-system            coredns-5c5df59fd4-jwf9q                              1/1     Running   0              112m
kube-system            ip-masq-agent-c6wzw                                   1/1     Running   0              113m
kube-system            ip-masq-agent-z87rp                                   1/1     Running   0              112m
kube-system            kube-dns-autoscaler-55c4f55869-rdvvv                  1/1     Running   0              115m
kube-system            kube-proxy-r9xzs                                      1/1     Running   0              113m
kube-system            kube-proxy-tfrrs                                      1/1     Running   0              112m
kube-system            metrics-server-9b4bf686c-55lr2                        2/2     Running   0              112m
kube-system            npd-v0.8.0-9724z                                      1/1     Running   0              112m
kube-system            npd-v0.8.0-pdqtv                                      1/1     Running   0              113m
kube-system            yc-disk-csi-node-v2-jgk5d                             6/6     Running   0              113m
kube-system            yc-disk-csi-node-v2-qbtpp                             6/6     Running   0              112m
kubernetes-dashboard   dashboard-metrics-scraper-64bcc67c9c-lgtzd            1/1     Running   0              25s
kubernetes-dashboard   kubernetes-dashboard-5c8bd6b59-lnplz                  1/1     Running   0              27s
```
Получаем `Bearer Token` для `ServiceAccount`

```
kubectl -n kubernetes-dashboard create token admin-user
```
выполняем `kubectl proxy`, Dashboard UI открывается через URL http://localhost:8001/api/v1/namespaces/kubernetes-dashboard/services/https:kubernetes-dashboard:/proxy/

Вводим токен для авторизации и попадаем в `dashboard`.

![Alt text](k8s_dashboard.jpg)

# HW17 Введение в kubernetes.

## В процессе выполнения ДЗ выполнены следующие мероприятия:

1. Описано тестовое приложение в контексте `Kubernetes` с помощью манифестов в формате `yaml`. Для каждого сервиса создан `Deployment манифест`;
Каталог с подготовленными манифестами `./kubernetes/reddit`. Использованы подготовленные в предыдущих ДЗ контейнеры: `skyfly534/comment`, `skyfly534/post`, `skyfly534/ui`.

2. Подняты при помощи `terraform` две ноды для установки `k8s` с требуемвми характеристиками:
 - RAM 4
 - CPU 4
 - SSD 40 GB
Процедура развертывания нод была взята из предыдущих ДЗ с небольшими доработками (`./kubernetes/terraform`);

3. Подготовлена конфигурация `Ansible` для развертывания `кластера k8s`: одна нода выполняет роль `master` , вторая - `worker`;
Динамический инвентори берем также из предыдущих ДЗ. Убеждаемся в работоспособности:

```
ansible all -m ping
178.154.204.151 | SUCCESS => {
    "ansible_facts": {
        "discovered_interpreter_python": "/usr/bin/python3"
    },
    "changed": false,
    "ping": "pong"
}
158.160.123.51 | SUCCESS => {
    "ansible_facts": {
        "discovered_interpreter_python": "/usr/bin/python3"
    },
    "changed": false,
    "ping": "pong"
}
```

Прописываем хосты, запускаем playbook на исполнение:

```
ansible-playbook -vv k8s_kubeadm.yml
```
После завершения работы плейбука проверяем состояние кластера на `master` ноде:

```
kubectl get nodes
NAME                   STATUS   ROLES           AGE     VERSION
fhm1d49tbkqfgj81so5v   Ready    control-plane   2m16s   v1.28.2
fhm3bvdi0qvsn4eahq2u   Ready    <none>          76s     v1.28.2
```
4. Применены подготовленные манифесты :

```
kubectl apply -f <manifest>.yml
```
Смотрим результат:

```
kubectl get pods
NAME                                  READY   STATUS    RESTARTS   AGE
comment-deployment-6d94947df4-2ljsm   1/1     Running   0          36s
mongo-deployment-f95c7c4fd-pj4ll      1/1     Running   0          27s
post-deployment-754f5447d7-ctjxt      1/1     Running   0          20s
ui-deployment-67b674f4b-txzxl         1/1     Running   0          12s
```
# HW16 Введение в мониторинг. Системы мониторинга.

## В процессе выполнения ДЗ выполнены следующие мероприятия:

1. Создан Docker хост в Yandex Cloud;

```
yc compute instance create \
  --name docker-host \
  --zone ru-central1-c \
  --network-interface subnet-name=default-ru-central1-c,nat-ip-version=ipv4 \
  --create-boot-disk image-folder-id=standard-images,image-family=ubuntu-1804-lts,size=15 \
  --ssh-key ~/.ssh/id_rsa.pub
```

и инициализировано окружение Docker;

```
docker-machine create \
  --driver generic \
  --generic-ip-address=51.250.32.67 \
  --generic-ssh-user yc-user \
  --generic-ssh-key ~/.ssh/id_rsa  \
  docker-host

eval $(docker-machine env docker-host)
```

2. Запущен контейнер с системой мониторинга `Prometheus` из готовым образом с `DockerHub`;

```
$ docker run --rm -p 9090:9090 -d --name prometheus prom/prometheus
```

3. Изучены web интерфейс системы мониторинга, метрики по умолчанию;


4. Изучен раздел `Targets` (цели) и формат собираемых метрик, доступных по адресу `host:port/metrics`;

5. Создан `Dockerfile` ( ./monitoring/prometheus/Dockerfile) при помощи которого копируем файл конфигурации `prometheus.yml` с "нашей" машины внутрь контейнера;

6. Созданы образы микросервисов `ui`, `post-py` и `comment` при помощи скриптов `docker_build.sh`, которые есть в директории каждого сервиса соответственно для добавления информации из Git в наш `healthcheck`;

```
/src/ui $ bash docker_build.sh
/src/post-py $ bash docker_build.sh
/src/comment $ bash docker_build.sh
```
или сразу все из корня репозитория

```
for i in ui post-py comment; do cd src/$i; bash docker_build.sh; cd -; done
```
7. Создан файл `docker/docker-compose.yml` для совместного развертывания микросервисов `ui`, `post-py`, `comment` и системы мониторинга `Prometheus`;

8. Добавлен сервис `prom/node-exporter:v0.15.2` в `docker/docker-compose.yml` для сбора информации о работе Docker хоста (нашей ВМ) и представления этой информации в Prometheus;

![Alt text](Prom1.jpg)

### Ссылка на докер хаб с собранными образами

```
https://hub.docker.com/repositories/skyfly534
```
## Дополнительные задания

9. Добавлен сервис `percona/mongodb_exporter:0.40` в `docker/docker-compose.yml` для сбора информации о работе СУБД `MongoDB` и представления этой информации в Prometheus;

docker-compose.yml:

```
...

mongo-exporter:
    image: percona/mongodb_exporter:0.40
    command:
      - '--mongodb.uri=mongodb://post_db:27017'
      - '--collect-all'
      - '--log.level=debug'
    ports:
      - '9216:9216'
    networks:
      - back_net

...
```
prometheus.yml:

```
...

- job_name: 'mongodb'
    static_configs:
      - targets:
        - 'mongo-exporter:9216'

...
```
10. Добавлен мониторинг сервисов `comment`, `post`, `ui` в Prometheus с помощью `Blackbox exporter`;

monitoring/blackbox/Dockerfile:

```
FROM prom/blackbox-exporter:latest
ADD config.yml /etc/blackbox_exporter/
```

monitoring/blackbox/config.yml:

```
modules:
  http_2xx:
    prober: http
    timeout: 5s
    http:
      valid_http_versions: ["HTTP/1.1", "HTTP/2.0"]
      valid_status_codes: []
      method: GET
      follow_redirects: false
```
docker-compose.yml:

```
...

blackbox-exporter:
    image: ${USERNAMEDEVOPS}/blackbox-exporter
    networks:
      - front_net
    depends_on:
      - ui
      - post
      - comment

...
```
monitoring/prometheus/prometheus.yml:

```
- job_name: 'blackbox'
    metrics_path: /metrics
    params:
      module: [http_2xx]
    static_configs:
      - targets:
        - http://ui:9292
        - http://comment:9292
        - http://post:9292
    relabel_configs:
      - source_labels: [__address__]
        target_label: __param_target
      - source_labels: [__param_target]
        target_label: instance
      - target_label: __address__
        replacement: blackbox-exporter:9115

```
### Итоговый список endpoint-ов Prometheus

![Alt text](Prom2.jpg)

11. Написаны `Makefile` в каждом из каталогов `./src/ui/Makefilecd`, `./src/post-py/Makefilecd`, `./src/comment/Makefilecd` и `./src/Makefilecd` , которые "билдят" либо "пушат" каждые образ по отдельности, либо все сразу.

Для сборки отдельного образа выполняем `make` в соответствующем каталоге. Для "пуша" в `DockerHub` выполняем `make push`. Эти же команды в родительском каталоге будут действовать на все три сервиса.

# HW15 Устройство Gitlab CI. Построение процесса непрерывной поставки.

## В процессе выполнения ДЗ выполнены следующие мероприятия:

1. Подготовлен образ ВМ при помощи `packer` с минимальными для `Gitlab CI` требованиями;

 - 2 core СPU
 - 4 GB RAM
 - 50 GB HDD

Изначально созданный файл конфига образа `docker.json`, был преобразован средствами packer в формат `HCL`

```
packer hcl2_upgrade -with-annotations ./packer/docker.json
```
В результате был сформирован файл конфига `./gitlab-ci/packer/docker.json.pkr.hcl` и сформирован файл с переменными `./gitlab-ci/packer/yandex.pkrvars.hcl`.

Проверка шаблона и запуск сборки образа

```
packer validate -var-file=yandex.pkrvars.hcl docker.json.pkr.hcl

packer build -var-file=yandex.pkrvars.hcl docker.json.pkr.hcl
```

2. Запущена ВМ из образа `packer` при помощи `terraform`;

В кталоге `./gitlab-ci/terraform/` выполняем следующие команды:

```
terraform validate

terraform apply
```

3. При помощи ansible playbook `./gitlab-ci/ansible/gitlab_ci_in_docker.yml` развернут `Gitlab` в контейнере;

Используем плагин inventory для YC из предыдущих ДЗ.

Для работы с контейнерами используем модуль  `docker_container_module`.

```
$ ansible-playbook gitlab_ci_in_docker.yml

PLAY [Gitlab CI deployment in Docker] ****************************************************************************

TASK [Gathering Facts] *******************************************************************************************
ok: [51.250.85.59]

TASK [create dirs for data volumes] ******************************************************************************
changed: [51.250.85.59] => (item=/srv/gitlab/config)
changed: [51.250.85.59] => (item=/srv/gitlab/logs)
changed: [51.250.85.59] => (item=/srv/gitlab/data)

TASK [install PIP] ***********************************************************************************************
changed: [51.250.85.59]

TASK [install Docker] ********************************************************************************************
changed: [51.250.85.59]

TASK [Gitlab CI deployment in Docker] ****************************************************************************
changed: [51.250.85.59]

PLAY RECAP *******************************************************************************************************
51.250.85.59               : ok=5    changed=4    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
```
После запуска открываем браузер и идем на `http://51.250.85.59` (внешний IP ВМ).

Login для первого входа `root`. Что узнать пароль заходим на ВМ и выполняем следующую команду:

```
sudo docker exec -it gitlab grep 'Password:' /etc/gitlab/initial_root_password
```
где `gitlab` имя контейнера.

4. Через веб-интерфейс создана группа `homework`, в ней проект `example`. Склонирован репозиторий на локальную машину;

```
git clone http://51.250.85.59/homework/example.git
```
так же понадобятся аутентификационные данные описанные выше.

5. В корне репозитория создана начальная версия тестового пайплайна `./.gitlab-ci.yml` и запушина в репозиторий;

```
git add .gitlab-ci.yml

git commit -m "Add pipeline definition"

git push
```
В `CI/CD -> Pipelines` видим, что запушеный пайплайн застрял в состоянии `pending`. Необходимо установить раннеры, которые могут выполнять работу.

6. Установлен, запущен и зарегистрирован раннер (в контейнере);

```
sudo mkdir -p /srv/gitlab-runnner/config

docker run -d --name gitlab-runner --restart always -v /srv/gitlab-
runner/config:/etc/gitlab-runner -v /var/run/docker.sock:/var/run/docker.sock
gitlab/gitlab-runner:latest

docker exec -it gitlab-runner gitlab-runner register \
--url http://51.250.85.59/ \
--non-interactive \
--locked=false \
--name DockerRunner \
--executor docker \
--docker-image alpine:latest \
--registration-token GR13489417h3XsW7nxUeqx1U3MLnR \
--tag-list "linux,xenial,ubuntu,docker" \
--run-untagged
```
Пайплайн вышел из застрявшего состояния, отработал без ошибок.

7. Добавлено приложение `reddit` в проект;

```
git clone https://github.com/express42/reddit.git

Не забываем удалить каталог .git у склонированного иначе не запуши
rm -rf ./reddit/.git

git add reddit/

git commit -m "Add reddit app"

git push
```
8. Добавлен запуск тестов приложения `reddit` в пайплайн;

```
image: ruby:2.4.2
stages:
...

variables:
  DATABASE_URL: 'mongodb://mongo/user_posts'
before_script:
  - cd reddit
  - bundle install
...

test_unit_job:
  stage: test
  services:
    - mongo:latest
  script:
    - ruby simpletest.rb
...
```

Создан файл с тестом `reddit/simpletest.rb`

```
require_relative './app'
require 'test/unit'
require 'rack/test'

set :environment, :test

class MyAppTest < Test::Unit::TestCase
  include Rack::Test::Methods

  def app
    Sinatra::Application
  end

  def test_get_request
    get '/'
    assert last_response.ok?
  end
end
```

В `reddit/Gemfile` добавлена библиотека `rack-test` для тестирования

```
...
gem 'sinatra', '~> 2.0.1'
gem 'haml'
gem 'bson_ext'
gem 'bcrypt'
gem 'puma'
gem 'mongo'
gem 'json'
gem 'rack-test' <---
...
```
9. Добавлены окружения `dev`, `beta (stage)` и `production`;

```
stages:
- build
- test
- review <---
...

build_job:
...
test_unit_job:
...

test_integration_job:
...

deploy_dev_job:
  stage: review
  script:
    - echo 'Deploy'
  environment:
    name: dev
    url: http://dev.example.com
```

```
- build
   - test
   - review
   - stage      <---
   - production <---
...

staging: # stage окружение
  stage: stage
  when: manual
  script:
    - echo 'Deploy'
  environment:
    name: beta
    url: http://beta.example.com

production: # production окружение
  stage: production
  when: manual
  script:
    - echo 'Deploy'
  environment:
    name: production
    url: http://example.com
```

10. Дбавлено условие, при котором на `stage` и `production` пойдут только те ветки, которые отмечены `тегом`;

```
staging: # stage окружение
  stage: stage
  when: manual
  only: # условие, при котором на stage пойдут только те ветки, которые отмечены тегом
    - tags
  script:
    - echo 'Deploy'
  environment:
    name: beta
    url: http://beta.example.com

production: # production окружение
  stage: production
  when: manual
  only: # условие, при котором на production пойдут только те ветки, которые отмечены тегом
    - tags
  script:
    - echo 'Deploy'
  environment:
    name: production
    url: http://example.com
```
11. Cоздано динамические окружение для всех веток, исключая главную ветку `main`;

```
branch_review:
  stage: review
  script: echo "Deploy to $CI_ENVIRONMENT_SLUG"
  environment:
    name: branch/$CI_COMMIT_REF_NAME
    url: http://$CI_ENVIRONMENT_SLUG.example.com
  only:
    - branches
  except:
    - main
```
## Дополнительное задание

12. В этап пайплайна `build` добавлен запуск контейнера с приложением `reddit`. Контейнер с reddit деплоился на окружение, динамически создаваемое для каждой ветки в Gitlab;

```
reddit_run:
  stage: build
  environment:  # Выкачивает с dockerhub образ приложения skyfly534/otus-reddit:1.0 и запускает контейнер с reddit
    name: branch/$CI_COMMIT_REF_NAME
    url: http://$CI_ENVIRONMENT_SLUG.example.com
  image: skyfly534/otus-reddit:1.0
  before_script:
    - echo 'Docker for run reddit'
  script:
    - echo 'Run reddit'
```
используем для выполнения задания подготовленный в предыдущем ДЗ образ приложения `skyfly534/otus-reddit:1.0` и загруженный на  `dockerhub`

13. Автоматизированно развёртывание `GitLab Runner` при помощи Ansible плейбук `./gitlab-ci/ansible/gitlab_runner_in_docker.yml`.

Регистрация пройдет только при запуске плейбука с тегом `registration`. Перед запуском плейбука необходимо внести `URL CI` сервера и регистрационный `токен` для runner. Переменные не вынесены в файл `.env` для наглядности.

# HW14 Docker: сети, docker-compose.

## В процессе выполнения ДЗ выполнены следующие мероприятия:

1. Изучена работа контейнера с различными сетевыми драйверами `none`, `host`;

```
docker run -ti --rm --network none joffotron/docker-net-tools -c ifconfig

docker run -ti --rm --network host joffotron/docker-net-tools -c ifconfig

docker run --network host -d nginx (запускаем несколько раз)
```
Вывод `docker logs <CONTAINER ID nginx>` говорит о том, что все контейнеры nginx кроме первого остановленны, т.к. сеть хоста одна, а порт занят первым запущенным контейнером.

```
nginx: [emerg] bind() to [::]:80 failed (98: Address already in use)
```

2. Изучена работа с сетевыми алиасами при запуске тестового проекта `Microservices Reddit` с использованием `bridge-сети`;

```
docker network create reddit --driver bridge

docker run -d --network=reddit --network-alias=post_db --network-alias=comment_db mongo:4
docker run -d --network=reddit --network-alias=post skyfly534/post:1.0
docker run -d --network=reddit --network-alias=comment skyfly534/comment:2.0
docker run -d --network=reddit -p 9292:9292 skyfly534/ui:3.0
```

3. Запущен проект в 2-х bridge сетях `back_net` и `front_net`, чтобы сервис `ui` не имел доступа к `базе данных`;

```
docker network create back_net --subnet=10.0.2.0/24
docker network create front_net --subnet=10.0.1.0/24

docker run -d --network=front_net -p 9292:9292 --name ui  skyfly534/ui:3.0
docker run -d --network=back_net --name comment  skyfly534/comment:2.0
docker run -d --network=back_net --name post  skyfly534/post:1.0
docker run -d --network=back_net --name mongo_db --network-alias=post_db --network-alias=comment_db mongo:4

docker network connect front_net post
docker network connect front_net comment
```

4. Изучен сетевой и правила `iptables` стек после запуска проекта;

```
docker-machine ssh docker-host
sudo apt-get update && sudo apt-get install bridge-utils

docker network ls

ifconfig | grep br

brctl show <interface>
```

```
sudo iptables -nL -t nat
```

## Docker-compose.

5. Файл `docker-compose.yml` (указанный в методичке) переработан для работы с 2-мя сетями и сетевыми алиасами. Произведена параметризация с помощью переменных окружения (файле `.env`);

```
# Переменные для Docker-compose.yml
COMPOSE_PROJECT_NAME=reddit
USERNAMEDEVOPS=skyfly534
VER_DB=3.2
DB_PATH=/data/db
VER_UI=3.0
UI_PORT=80
VER_POST=1.0
VER_COMMENT=2.0
```

Базовое имя образа формируется из названия папки и названия контейнера. Его можно изменить при помощи переменной окружения `COMPOSE_PROJECT_NAME`, либо указать в параметре ключа `-p` при запуске docker compose.

## Дополнительное задание

6. При помощи файла `docker-compose.override.yml` переопределена базовая конфигурация с целью переопределения инструкции command контейнеров `comment` и `ui` и для создания `volumes` (каталогов) и осуществления импорта кодом приложения внутрь контейнеров.

```
version: '3.3'
services:

  ui:
    command: puma --debug -w 2
    volumes:
      - ./ui:/app

  post:
    volumes:
      - ./post-py:/app

  comment:
    command: puma --debug -w 2
    volumes:
      - ./comment:/app
```

# HW13 Docker-образы. Микросервисы.

## В процессе выполнения ДЗ выполнены следующие мероприятия:

1. Для выполнения домашнего задания и дальнейшей работы с Docker-
образами установлен и протестирован `linter`;

```
$ /bin/hadolint Dockerfile
Dockerfile:6 DL3013 warning: Pin versions in pip. Instead of `pip install <package>` use `pip install <package>==<version>` or `pip install --requirement <requirements file>`
Dockerfile:6 DL3018 warning: Pin versions in apk add. Instead of `apk add <package>` use `apk add <package>=<version>`
Dockerfile:6 DL3042 warning: Avoid use of cache directory with pip. Use `pip install --no-cache-dir <package>`
```
2. Cоздана необходимая структура для развертывания приложения;

Пприложение состоит из трех компонентов:

`post-py` - сервис отвечающий за написание постов

`comment` - сервис отвечающий за написание комментариев

`ui` - веб-интерфейс, работающий с другими сервисами

также требуется база данных `MongoDB`

3. Для каждого сервиса создан `Dockerfile` для дальнейшего создания образа контейнеров;

4. Собраны образы с сервисами `post:1.0`, `comment:1.0`, `ui:1.0`;

```
docker pull mongo:4
docker build -t skyfly534/post:1.0 ./post-py
docker build -t skyfly534/comment:1.0 ./comment
docker build -t skyfly534/ui:1.0 ./ui
docker network create reddit
```

В процессе сборки для замены неотвечающего репозитория задействован архивный репозиторий deb http://archive.debian.org/debian stretch main:

```
FROM ruby:2.2
RUN set -x \
 && echo "deb http://archive.debian.org/debian stretch main" > /etc/apt/sources.list \
 && apt-get update -qq \
 && apt-get install -y build-essential \
 && apt-get clean
```
5. Создана bridge-сеть для контейнеров с именем `reddit`;

6. Запущены контейнеры c `сетевыми алиасами`  из подготовленных образов;

```
docker run -d --network=reddit --network-alias=post_db --network-alias=comment_db mongo:4
docker run -d --network=reddit --network-alias=post skyfly534/post:1.0
docker run -d --network=reddit --network-alias=comment skyfly534/comment:1.0
docker run -d --network=reddit -p 9292:9292 skyfly534/ui:1.0
```
При использлвании самой свежей `mongo` приложение возвратило ошибку (Can't show blog posts, some problems with the post service), вызвана она тем, что используется слишком старый драйвер БД. Запускаем БД версии ниже 6.

Проверели прриложение, зашли на `http://<docker-host-ip>:9292/`

## Дополнительное задание

7. Запущены контейнеры с другими сетевыми алиасами;

Переменные окружения при этом заданы через параметр `-e`

```
docker run -d --network=reddit --network-alias=skyfly_post_db --network-alias=skyfly_comment_db mongo:4
 docker run -d --network=reddit --network-alias=skyfly_post -e POST_DATABASE_HOST=skyfly_post_db skyfly534/post:1.0
 docker run -d --network=reddit --network-alias=skyfly_comment -e COMMENT_DATABASE_HOST=skyfly_comment_db skyfly534/comment:1.0
 docker run -d --network=reddit -p 9292:9292 -e POST_SERVICE_HOST=skyfly_post -e COMMENT_SERVICE_HOST=skyfly_comment skyfly534/ui:1.0

```

8. Создан новый Dockerfile для сервиса ui, новый образ `skyfly534/ui:2.0` собран на базе `ubuntu:16.04`;

Произведена сверка размеров образов:

```
docker images
REPOSITORY          TAG       IMAGE ID       CREATED              SIZE
skyfly534/ui        1.0       b94659d48b1b   About a minute ago   999MB
skyfly534/ui        2.0       64cc255f75da   7 minutes ago        485MB
skyfly534/comment   1.0       1beacb74836b   11 minutes ago       996MB
skyfly534/post      1.0       8120ff85bbb3   13 minutes ago       67.2MB
mongo               4         a04ee971f462   4 days ago           434MB
```

## Дополнительное задание

9. Созданы новые Dockerfile для сервисов ui и comment, новые образы `skyfly534/ui:3.0` и `skyfly534/comment:2.0` собранs на базе `alpine:3.14`;

Произведена сверка размеров образов:

```
docker images
REPOSITORY          TAG       IMAGE ID       CREATED         SIZE
skyfly534/ui        3.0       8c509ac24622   9 minutes ago   93.6MB
skyfly534/ui        1.0       b94659d48b1b   4 hours ago     999MB
skyfly534/ui        2.0       64cc255f75da   4 hours ago     485MB
skyfly534/comment   1.0       1beacb74836b   4 hours ago     996MB
skyfly534/post      1.0       8120ff85bbb3   4 hours ago     67.2MB
mongo               4         a04ee971f462   4 days ago      434MB
```
10. Создан Docker volume reddit_db и подключен в контейнер с MongoDB по пути /data/db.

```
docker run -d --network=reddit --network-alias=post_db --network-alias=comment_db -v reddit_db:/data/db mongo:4
```
Произведена проверка путем проверки наличия написанного поста в приложении после пересоздания контейнеров.

На память

```
docker pull mongo:4

docker build -t skyfly534/post:1.0 ./post-py
docker build -t skyfly534/comment:2.0 ./comment
docker build -t skyfly534/ui:3.0 ./ui

docker network create reddit

docker run -d --network=reddit --network-alias=post_db --network-alias=comment_db mongo:4
docker run -d --network=reddit --network-alias=post skyfly534/post:1.0
docker run -d --network=reddit --network-alias=comment skyfly534/comment:2.0
docker run -d --network=reddit -p 9292:9292 skyfly534/ui:3.0
```
# HW12 Технология контейнеризации. Введение в Docker.

## В процессе выполнения ДЗ выполнены следующие мероприятия:

1. Установлен `Docker` по официальной документации. Проверена версия установленного ПО;

2. Текущий пользователь добавлен к группе безопасности `docker` (для работы без `sudo`);

```
sudo groupadd docker

sudo usermod -aG docker $USER

newgrp docker
```

3. Скачан и запущен теcтовый контейнер;

```
docker run hello-world
```

4. Изучены и выполнены основные команды docker;

не забываем все чистить

```
docker rm $(docker ps -a -q)

docker rmi $(docker images -q)
```
## Дополнительное задание

5. На основе вывода команд описаны отличия контейнера от образа в файле `/docker-monolith/docker-1.log`;

## Docker-контейнеры

6. Проверенны настойки `Yandex Cloud CLI` (были сделаны ранее);

7. Создан хост и инициализировано окружение `Docker` на нем `docker-machine create`;

```
yc compute instance create \
--name docker-host \
--zone ru-central1-a \
--network-interface subnet-name=default-ru-central1-a,nat-ip-version=ipv4 \
--create-boot-disk image-folder-id=standard-images,image-family=ubuntu-1804-
lts,size=15 \
--ssh-key ~/.ssh/id_rsa.pub

 docker-machine create \
--driver generic \
--generic-ip-address=<ПУБЛИЧНЫЙ_IP_СОЗДАНОГО_ВЫШЕ_ИНСТАНСА> \
--generic-ssh-user yc-user \
--generic-ssh-key ~/.ssh/id_rsa \
docker-host

docker-machine ls

eval $(docker-machine env docker-host)
```

8. Организована необходимая структура репозитория;

9. Произведена сборка образа `reddit:latest`;

```
docker build -t reddit:latest .
```
10. После сборки образа на хосте YC c инициализированysv окружение `Docker` запущен контейнер;

```
docker run --name reddit -d --network=host reddit:latest
```
Проверенна работа созданного контейнера `http://<ПУБЛИЧНЫЙ_IP_СОЗДАНОГО_ИНСТАНСА>:9292`

11. Пройдена регистрация на `https://hub.docker.com` с последующей аутентификацией;

```
docker login
Login with your Docker ID to push and pull images from Docker Hub.
If you don't have a Docker ID, head over to https://hub.docker.com to create one.
Username: your-login
Password:
Login Succeeded
```
12. Загружен созданный образ на docker hub;

```
docker tag reddit:latest skyfly534/otus-reddit:1.0

docker push skyfly534/otus-reddit:1.0
```
Проверена работа в локальном Docker

```
docker run --name reddit -d -p 9292:9292 skyfly534/otus-reddit:1.0
```
Проверенна работа созданного контейнера `http://localhost:9292`

## Дополнительное задание

13. При помощи `packer` подготовлен образ виртуальной машины с установленным `docker`, используется `provisioners` `ansible`, для установки `docker` и модуля `python`, плейбук `ansible/packer_docker.yml`;


```
packer build -var-file=variables.json docker.json
```

14. Инстансы поднимаются с помощью `Terraform`, их количество задается переменной `servers_count`;

```
terraform init

terraform apply
```

15. Написан плейбук Ansible `deploy_docker_app.yml` с использованием динамического инвентори (расмотренно ранее в ДЗ № 10) для установки докера и запуска (для запуска контейнера возьмём community.docker.docker_container) приложения.

```
ansible-inventory --list
{
    "_meta": {
        "hostvars": {
            "158.160.127.201": {
                "ansible_host": "158.160.127.201"
            },
            "62.84.125.16": {
                "ansible_host": "62.84.125.16"
            }
        }
    },
    "all": {
        "children": [
            "ungrouped"
        ]
    },
    "ungrouped": {
        "hosts": [
            "158.160.127.201",
            "62.84.125.16"
        ]
    }
}
```

```
ansible-playbook deploy_docker_app.yml

PLAY [Run reddit-docker] *****************************************************************************************

TASK [Install PIP] ***********************************************************************************************
ok: [158.160.127.201]
ok: [62.84.125.16]

TASK [Install Docker SDK for Python] *****************************************************************************
ok: [158.160.127.201]
ok: [62.84.125.16]

TASK [Run app in container] **************************************************************************************
changed: [62.84.125.16]
changed: [158.160.127.201]

PLAY RECAP *******************************************************************************************************
158.160.127.201            : ok=3    changed=1    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
62.84.125.16               : ok=3    changed=1    unreachable=0    failed=0    skipped=0    rescued=0    ignored=0
```
Я запускал два истанса, оба мне ответили по следующим адресам: `http://62.84.125.16`, `http://158.160.127.201`.

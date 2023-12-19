# skyfly535_microservices
skyfly535 microservices repository

# HW12 Технология контейнеризации. Введение в Docker.

## В процессе выполнения ДЗ выполнены следующие мероприятия:

1. Установлен `Docker` по официальной документации. Проверена версия установленного ПО;

2. Текущий пользователь добавлен к группе безоасности `docker` (для работы без `sudo`);

```
sudo groupadd docker

sudo usermod -aG docker $USER

newgrp docker
```

3. Скачан и запущен темтовый контейнер;

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
10. После сборки образа на хосте YC c инициализированysv окружение `Docker` запущен котейнер;

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

15. Написан плейбук Ansible `deploy_docker_app.yml` с использованием динамического инвентори (рассмотренно ранеев ДЗ № 10) для установки докера и запуска (для запуска контейнера возьмём community.docker.docker_container) приложения.

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

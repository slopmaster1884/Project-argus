Argus Node для Raspberry Pi / Argus Node for Raspberry Pi
==========================================================

Это SD-карта с готовой нодой Argus. Вставь её в Raspberry Pi (3, 4, 5, 400, 500, Zero 2 W),
подключи к домашней сети (кабель или Wi-Fi, настроенный в Raspberry Pi Imager), включи питание
и подожди ~2 минуты. На главном ПК: Argus -> Cluster -> «Найдено в сети» -> «Добавить».

This SD card holds a ready Argus node. Put it into a Raspberry Pi, connect it to your home network
(Ethernet cable, or Wi-Fi set in Raspberry Pi Imager), power it on and wait ~2 minutes.
On the main PC: Argus -> Cluster -> "Found on network" -> "Add".

Файлы здесь / Files here:
  argus.conf      настройки ноды (защищённый режим, имя, потоки) / node settings
  argus-pin.txt   PIN защищённого режима (появляется, только если он включён) / secured-mode PIN
  network-config  Wi-Fi без Imager (см. инструкцию) / Wi-Fi without Imager (see the guide)

Инструкция / Guide:
  https://github.com/slopmaster1884/Project-argus/blob/main/docs/RASPBERRY-PI.md
  https://github.com/slopmaster1884/Project-argus/blob/main/docs/RASPBERRY-PI.en.md

Только для домашней сети: без защищённого режима порт 50052 открыт для всех в этой сети.
Home network only: without secured mode, port 50052 is open to everyone on that network.

# Argus на Linux: пошагово, для тех, кто открыл терминал впервые

[English version](LINUX.en.md) · Второй Windows-ПК как нода: [PC-NODE.md](PC-NODE.md)

> Всё, что начинается с `$`, вводится в **Терминал** (без самого `$`).
> Открыть терминал: **Ctrl + Alt + T** (Ubuntu, Mint, Pop!_OS) или найти «Терминал» в меню.
> Вставить текст в терминал: **Ctrl + Shift + V** (обычный Ctrl+V там не работает).

## Самое быстрое: одна команда (сделать из этого Linux помощника-ноду)

Открой терминал, вставь строку и нажми Enter:

```
$ curl -fsSL https://raw.githubusercontent.com/slopmaster1884/Project-argus/main/scripts/install.sh | bash
```

Установщик сам проверит систему, скажет, чего не хватает (и спросит, прежде чем что-то ставить через `sudo`), откроет порт в файрволе (тоже спросит), включит автозапуск и в конце **крупно напишет IP-адрес** этого компьютера и что нажать в Argus. Подробности — в [разделе B](#b-linux--помощник-нода).

> Если пишет `curl: command not found` — сначала `sudo apt install curl` (Ubuntu/Mint), `sudo dnf install curl` (Fedora) или `sudo pacman -S curl` (Arch).

## Что ты хочешь сделать?

| Я хочу… | Иди в раздел |
|---|---|
| Запускать Argus на этом Linux-компьютере и общаться с нейросетью здесь | [A. Linux — главный компьютер](#a-linux--главный-компьютер) |
| Чтобы этот Linux-ноутбук/ПК **помогал** другому компьютеру с Argus | [B. Linux — помощник (нода)](#b-linux--помощник-нода) |
| Что-то не работает | [C. Если не работает](#c-если-не-работает) |

---

## 0. Узнай, какой у тебя Linux (30 секунд)

```
$ cat /etc/os-release | head -2
```

- Видишь **Ubuntu, Linux Mint, Pop!_OS, Debian, Zorin** — в командах ниже бери строки «Ubuntu/Mint».
- Видишь **Fedora** — бери строки «Fedora».
- Видишь **Arch, Manjaro, EndeavourOS, CachyOS** — бери строки «Arch».

## A. Linux — главный компьютер

### Шаг 1. Поставь драйвер видеокарты (Vulkan)

Argus считает на видеокарте через Vulkan. Проверь, есть ли он:

```
$ vulkaninfo --summary | grep deviceName
```

Если увидел название своей видеокарты — переходи к шагу 2. Если «command not found» или пусто:

| Система | Команда |
|---|---|
| Ubuntu/Mint | `sudo apt install mesa-vulkan-drivers vulkan-tools` |
| Fedora | `sudo dnf install mesa-vulkan-drivers vulkan-tools` |
| Arch | `sudo pacman -S vulkan-icd-loader vulkan-tools` + `vulkan-radeon` (AMD) / `vulkan-intel` (Intel) / `nvidia-utils` (NVIDIA) |

**NVIDIA на Ubuntu/Mint:** открой «Дополнительные драйверы» (Additional Drivers), выбери рекомендованный драйвер `nvidia-driver-…`, нажми «Применить», перезагрузись.

`sudo` спросит **твой** пароль от компьютера. Символы при вводе не видно — это нормально, просто набери и нажми Enter.

### Шаг 2. Скачай Argus

Открой [страницу релизов](https://github.com/slopmaster1884/Project-argus/releases) и скачай:
- **Ubuntu/Mint/Debian:** файл `.deb` → двойной клик → «Установить». Или в терминале:
  ```
  $ cd ~/Загрузки        # или ~/Downloads, если система на английском
  $ sudo apt install ./Argus_*.deb
  ```
- **Fedora, Arch и всё остальное:** файл `.AppImage`:
  ```
  $ cd ~/Загрузки
  $ chmod +x Argus_*.AppImage
  $ ./Argus_*.AppImage
  ```
  Если AppImage ругается на `libfuse.so.2`: Ubuntu 24.04+ `sudo apt install libfuse2t64`, Fedora `sudo dnf install fuse-libs`, Arch `sudo pacman -S fuse2`.

### Шаг 3. Разреши телефонам подключаться по USB (если будут телефоны)

| Система | Команда |
|---|---|
| Ubuntu/Mint | `sudo apt install android-sdk-platform-tools-common` |
| Fedora | `sudo dnf install android-tools` |
| Arch | `sudo pacman -S android-udev` |

Потом **выдерни и снова вставь** кабель телефона. Если Argus пишет «no permissions» — перезагрузи компьютер.

### Шаг 4. Запусти

Найди **Argus** в меню приложений → нажми **«Подобрать модель и запустить»** → жди статус «Готово» → пиши в чат. Дальше всё как на Windows: [README](../README.md#как-запустить).

---

## B. Linux — помощник (нода)

Ноутбук отдаёт свою память и процессор (или видеокарту) главному компьютеру с Argus. Оба устройства должны быть **в одной домашней Wi-Fi сети**.

Есть видеокарта? Сначала поставь Vulkan, как в [шаге A1](#шаг-1-поставь-драйвер-видеокарты-vulkan), — нода будет быстрее. Не обязательно: без Vulkan нода работает на процессоре.

### Шаг 1. Одна команда

```
$ curl -fsSL https://raw.githubusercontent.com/slopmaster1884/Project-argus/main/scripts/install.sh | bash
```

Что произойдёт (ничего не надо делать, только отвечать на вопросы `y` / `n`):

1. Проверит, что система 64-битная, и найдёт нужные программы. Если чего-то не хватает, покажет точную команду для твоего Linux и спросит, выполнить ли её. `sudo` попросит **твой** пароль от компьютера — символы при вводе не видны, это нормально.
2. Скачает скрипт ноды в папку `~/.local/share/argus-node`.
3. Если включён файрвол (ufw или firewalld), предложит открыть порт 50052. Отвечай `y` — иначе ноутбук будет «пропадать».
4. Включит автозапуск: нода будет сама стартовать при входе в систему. В первый раз она скачивает llama.cpp (~25–40 МБ) — подожди, пока побегут точки.
5. Спросит, запускать ли ноду сразу при включении компьютера, даже без входа. Для ноутбука-помощника удобно ответить `y`.
6. Напишет большими буквами **IP-адрес** и что нажать в Argus.

Хочешь, чтобы нода работала только пока открыто окно терминала (без автозапуска)?

```
$ curl -fsSL https://raw.githubusercontent.com/slopmaster1884/Project-argus/main/scripts/install.sh | bash -s -- --foreground
```

Остановить — **Ctrl + C**.

### Шаг 2. Добавь ноду на главном компьютере

В Argus: **Cluster → «Найдено в сети»** → у своего ноутбука нажми **«Добавить»**. Статус должен стать зелёным.

Ноутбука нет в списке? Там же нажми **«Добавить ноду по IP»** и впиши адрес, который показал установщик, с портом, например `192.168.1.23:50052`. Забыл адрес — узнай так:

```
$ hostname -I
```

(первое число вида `192.168.x.x`).

### Полезные команды

| Что | Команда |
|---|---|
| Нода работает? | `systemctl --user status argus-node` |
| Посмотреть журнал | `journalctl --user -u argus-node -f` (выход — Ctrl+C) |
| Остановить / запустить | `systemctl --user stop argus-node` / `systemctl --user start argus-node` |
| Открыть порт ещё раз | `bash ~/.local/share/argus-node/src/argus-node-linux.sh --open-firewall` |
| Удалить ноду совсем | `curl -fsSL https://raw.githubusercontent.com/slopmaster1884/Project-argus/main/scripts/install.sh \| bash -s -- --uninstall` |

### Вручную (если не любишь `curl | bash`)

```
$ git clone https://github.com/slopmaster1884/Project-argus.git
$ cd Project-argus
$ bash scripts/argus-node-linux.sh                 # работает, пока открыто окно
$ bash scripts/argus-node-linux.sh --open-firewall  # открыть порт 50052 (ufw/firewalld)
$ bash scripts/argus-node-linux.sh --systemd        # автозапуск
```

Выключить автозапуск: `bash scripts/argus-node-linux.sh --uninstall-systemd`.

Открыть порт руками:

| Система | Команда |
|---|---|
| Ubuntu/Mint (ufw) | `sudo ufw allow 50052/tcp` |
| Fedora (firewalld) | `sudo firewall-cmd --permanent --add-port=50052/tcp && sudo firewall-cmd --reload` |
| Arch | обычно файрвола нет, пропусти |

---

## C. Если не работает

| Что видишь | Что делать |
|---|---|
| Ноутбук есть в «Найдено в сети», но после «Добавить» становится **OFFLINE** | Порт закрыт файрволом. Открой порт: `bash ~/.local/share/argus-node/src/argus-node-linux.sh --open-firewall` (или таблица в [«Вручную»](#вручную-если-не-любишь-curl--bash)). |
| Ноутбука нет в «Найдено в сети» | Проверь, что оба в одной Wi-Fi сети (не гостевой). Добавь по IP ([шаг B2](#шаг-2-добавь-ноду-на-главном-компьютере)). Роутер может блокировать широковещание («изоляция клиентов» / AP isolation): переустанови ноду с адресом главного ПК: `curl -fsSL https://raw.githubusercontent.com/slopmaster1884/Project-argus/main/scripts/install.sh \| ARGUS_BEACON_TARGET=<IP главного ПК> bash` |
| «rpc-server протокол v… — нужен v8» | На ноутбуке другая версия llama.cpp. Удали ноду (команда «Удалить ноду совсем» выше) и поставь заново. |
| «rpc-server занят другим клиентом» | Ноду уже использует другой Argus. Нода обслуживает только один компьютер одновременно. |
| Нода работает очень медленно | Скрипт не нашёл Vulkan и взял версию для процессора. Поставь Vulkan ([шаг A1](#шаг-1-поставь-драйвер-видеокарты-vulkan)), удали ноду (`--uninstall`) и поставь заново. |
| Установщик пишет «32-битная система» | Нужна 64-битная ОС. На Raspberry Pi поставь Raspberry Pi OS (64-bit). |
| Установщик пишет «systemd --user недоступен» | Так бывает в WSL, контейнере или по ssh. Нода запустится в этом же окне; для автозапуска войди в систему обычным способом и запусти установщик снова. |
| Телефон по USB: «no permissions» | [Шаг A3](#шаг-3-разреши-телефонам-подключаться-по-usb-если-будут-телефоны), переподключи кабель, перезагрузись. |

Не помогло? Открой [Issue](https://github.com/slopmaster1884/Project-argus/issues/new), приложи:
1. вывод `cat /etc/os-release | head -2`;
2. последние 30 строк окна, где работает нода, или вывод `journalctl --user -u argus-node -n 30 --no-pager`;
3. на главном ПК — кнопку **«Копировать журнал»** и вставь текст.

## ⚠ Безопасность

Нода слушает порт 50052 без пароля. Запускай её **только дома**, не в кафе, общаге или на работе, и не пробрасывай порты 50052/50053 в интернет.

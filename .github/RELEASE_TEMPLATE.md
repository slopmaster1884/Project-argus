## Что скачать

Нужен **один файл** — под ваш компьютер. Остальное по желанию.

| У вас | Качайте |
|---|---|
| Windows 10/11 | **Argus-Setup.exe** — запустить и нажимать «Далее» |
| Linux (Ubuntu, Debian, Mint) | **Argus___VERSION___amd64.deb** — открыть двойным щелчком |
| Linux (любой другой) | **Argus___VERSION___amd64.AppImage** — сделать исполняемым и запустить ([инструкция](https://github.com/slopmaster1884/Project-argus/blob/main/docs/LINUX.md)) |

**Хотите добавить в кластер ещё устройства?** Это не обязательно, Argus работает и на одном ПК.

| Устройство-помощник | Качайте |
|---|---|
| Android-телефон | **Argus-Node.apk** — поставить на телефон |
| Raspberry Pi 4/5 | **argus-node-pi-arm64.img.xz** — записать на карту через Raspberry Pi Imager |
| Второй ПК на Linux | ничего качать не нужно, одна команда в терминале: `curl -fsSL https://raw.githubusercontent.com/slopmaster1884/Project-argus/main/scripts/install.sh \| bash` |

Файлы с пометкой «Служебное» (`install.sh`, `argus-node-linux.sh`, `SHA256SUMS.txt`, `.sha256`, манифест) качать руками не нужно: ими пользуются скрипты и сам Argus при обновлении.

---

### What to download (EN)
Windows → **Argus-Setup.exe**. Ubuntu/Debian → **.deb**. Other Linux → **.AppImage**. Optional helper devices: Android → **Argus-Node.apk**, Raspberry Pi → **.img.xz**. Everything marked «Служебное» is used by scripts and the updater.

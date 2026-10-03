# Протоколы и источники

Собственная реализация запросов чтения, без копирования драйверов в сборку. Нет команд изменения DPI, подсветки, привязки или прошивки.

Обнаружение: [RegisterDeviceNotificationW](https://learn.microsoft.com/en-us/windows/win32/api/winuser/nf-winuser-registerdevicenotificationw), [DEVPKEY_Device_ContainerId](https://learn.microsoft.com/en-us/windows-hardware/drivers/install/devpkey-device-containerid). Подписка существует только в главном процессе; дополнительные карточки не создают отдельных движков Flutter или процессов опроса.

| Устройство | Определение | Запрос | Ответ |
|---|---|---|---|
| MCHOSE A7 V2 Pro | VID `3837`, PID `100A`, usage page `FF01` | Feature report `11`, 20 инвертированных байтов, команда `06` | 21 байт; процент `raw[11] XOR FF`, зарядка `raw[12] XOR FF`; проверяются VID, заголовок, связь и диапазон |
| Galaxy70-2.4g | VID `05AC`, PID `024F`, точное имя, usage page `FF60`, usage `61`, отчёты 33 байта | Output `00 20 01 00 … 00 21` | Input `00 20 01 00 PP … CS`; процент `raw[4]`, сумма первых 32 байтов по модулю 256 в `raw[32]` |

MCHOSE: [описание протокола mchose-linux](https://github.com/alexfrih/mchose-linux/blob/main/PROTOCOL.md), проверенное реальным ответом. Низкие проценты не умножаются на 10.

Galaxy70: [официальный драйвер Epomaker 1.0.0.0](https://epomaker.com/blogs/software/epomaker-galaxy70-driver). Драйвер распакован для исследования, не установлен. Функция чтения батареи в `DeviceDriver.exe` (x86, timestamp 663EE559) по VA `00435EB0`; сборка пакета/обмен по `004501C0`, передача по `00451DF0`, чтение со снятием нулевого report ID по `00451ED0`. На устройстве подтверждён пакет `00 20 01 00 5f … 80` (95%). Исследовательские файлы в `research/` исключены из git и portable-сборки.

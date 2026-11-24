"""Stand-in UDisks2 service for the integration test: one ATA SSD and one NVMe drive on the bus at
DBUS_SYSTEM_BUS_ADDRESS. The ATA values are a recording from a real SSD with the serial number and WWN replaced.
"""

import asyncio

from dbus_fast import BusType, Message, MessageType, Variant
from dbus_fast.aio import MessageBus

UDISKS = "org.freedesktop.UDisks2"
DRIVES = "/org/freedesktop/UDisks2/drives"
ATA_PATH = f"{DRIVES}/Micron_1100_SATA_256GB_TESTSERIAL0001"
NVME_PATH = f"{DRIVES}/Example_NVMe_SSD_1TB_TESTSERIAL0002"
NO_EXPANSION = {}

OBJECTS = {
    ATA_PATH: {
        f"{UDISKS}.Drive": {
            "Model": Variant("s", "Micron 1100 SATA 256GB"),
            "Vendor": Variant("s", ""),
            "Revision": Variant("s", "M0DL022"),
            "Serial": Variant("s", "TESTSERIAL0001"),
            "WWN": Variant("s", "0x5000000000000001"),
            "Id": Variant("s", "Micron-1100-SATA-256GB-TESTSERIAL0001"),
        },
        f"{UDISKS}.Drive.Ata": {
            "SmartSupported": Variant("b", True),
            "SmartEnabled": Variant("b", True),
            "SmartUpdated": Variant("t", 1795460755),
            "SmartFailing": Variant("b", False),
            "SmartPowerOnSeconds": Variant("t", 21675600),
            "SmartTemperature": Variant("d", 313.15),
            "SmartNumAttributesFailing": Variant("i", 0),
            "SmartNumBadSectors": Variant("x", 0),
        },
    },
    NVME_PATH: {
        f"{UDISKS}.Drive": {
            "Model": Variant("s", "Example NVMe SSD 1TB"),
            "Vendor": Variant("s", ""),
            "Revision": Variant("s", "1.0"),
            "Serial": Variant("s", "TESTSERIAL0002"),
            "WWN": Variant("s", ""),
            "Id": Variant("s", "Example-NVMe-SSD-1TB-TESTSERIAL0002"),
        },
        f"{UDISKS}.NVMe.Controller": {
            "SmartUpdated": Variant("t", 1795460755),
            "SmartCriticalWarning": Variant("as", []),
            "SmartPowerOnHours": Variant("t", 1234),
            "SmartTemperature": Variant("q", 308),
        },
    },
    # A drive without SMART (a USB stick): no Drive.Ata or NVMe.Controller interface.
    f"{DRIVES}/USB_Stick_TESTSERIAL0003": {
        f"{UDISKS}.Drive": {
            "Model": Variant("s", "USB Stick"),
            "Vendor": Variant("s", "Example"),
            "Revision": Variant("s", "1.0"),
            "Serial": Variant("s", "TESTSERIAL0003"),
            "WWN": Variant("s", ""),
            "Id": Variant("s", "USB-Stick-TESTSERIAL0003"),
        },
    },
}

ATA_ATTRIBUTES = [
    [0x05, "reallocated-sector-count", 51, 100, 100, 10, 0, 3, NO_EXPANSION],
    [0x09, "power-on-hours", 50, 100, 100, 0, 21675600000, 2, NO_EXPANSION],
    [0x0C, "power-cycle-count", 51, 100, 100, 1, 274, 1, NO_EXPANSION],
    [0xB1, "wear-leveling-count", 51, 81, 81, 10, 295, 1, NO_EXPANSION],
    [0xBB, "reported-uncorrect", 51, 100, 100, 1, 0, 3, NO_EXPANSION],
    [0xC2, "temperature-celsius-2", 34, 60, 22, 0, 313150, 4, NO_EXPANSION],
    [0xC7, "udma-crc-error-count", 50, 100, 100, 0, 0, 1, NO_EXPANSION],
    [0xB4, "unused-reserved-blocks", 51, -1, -1, 0, 2049, 1, NO_EXPANSION],
]

NVME_ATTRIBUTES = {
    "avail_spare": Variant("y", 100),
    "spare_thresh": Variant("y", 10),
    "percent_used": Variant("y", 3),
    "total_data_written": Variant("t", 12_345_000_000_000),
    "media_errors": Variant("t", 0),
}


def handle(msg):
    if msg.message_type != MessageType.METHOD_CALL:
        return None
    if msg.member == "GetManagedObjects":
        return Message.new_method_return(msg, "a{oa{sa{sv}}}", [OBJECTS])
    if msg.member == "SmartGetAttributes" and msg.path == ATA_PATH:
        return Message.new_method_return(msg, "a(ysqiiixia{sv})", [ATA_ATTRIBUTES])
    if msg.member == "SmartGetAttributes" and msg.path == NVME_PATH:
        return Message.new_method_return(msg, "a{sv}", [NVME_ATTRIBUTES])
    return None


async def main():
    bus = await MessageBus(bus_type=BusType.SYSTEM).connect()
    bus.add_message_handler(handle)
    await bus.request_name(UDISKS)
    print("fake UDisks2 ready", flush=True)
    await bus.wait_for_disconnect()


asyncio.run(main())

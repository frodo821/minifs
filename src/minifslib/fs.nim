# This is just an example to get you started. Users of your hybrid library will
# import this file by writing ``import bootfspkg/submodule``. Feel free to rename or
# remove this file altogether. You may create additional modules alongside
# this file as required.
import strformat, tables
import ./lowlevel

type
  FSInfo* = ref object
    jmp*: array[2, char]             # 0
    signature*: array[4, char]       # 2
    oemName*: array[8, char]         # 6
    bytesPerSector*: int16           # 14
    sectorPerCluster*: int8          # 16
    reservedSectors*: int16          # 17
    fsVersion*: array[2, int8]       # 19
    driveNumber*: int8               # 21
    bootFlag*: int8                  # 22
    volumeId*: int32                 # 23
    tableAddr: int16                 # 28
    volumeLabel*: array[11, char]    # 29
    bootCode*: array[470, char]      # 40
    mbrSignature*: array[2, char]    # 510

  FileTable* = ref object
    extraLength*: int16
    entries*: int16

  FileTableEntry* = ref object
    sector*: int32
    id*: int32
    name*: array[32, char]
    flags*: int8
    parentNode*: int32
    reference*: int32

const FileTableSize* = sizeof(FileTable)
const FileTableEntrySize* = sizeof(FileTableEntry)

const jmpOp = ['\xeb', '\x26']
const nop = ['\xeb', '\0']

proc loadFSInfo*(path: string): FSInfo =
  let file = open(path, fmRead)
  let buffer = alloc(512)
  let read = file.readBuffer(buffer, 512)

  defer:
    file.close()
    dealloc(buffer)

  if read != 512:
    raise newException(ValueError, "Not enough volume size!")

  if result.signature != ['D', 'H', 'M', 'O']:
    raise newException(ValueError, "Invalid file system signature.")
  if result.mbrSignature != ['\x55', '\xaa']:
    raise newException(ValueError, "Invalid MBR signature.")
  if result.bytesPerSector mod 512'i16 != 0'i16:
    raise newException(ValueError, "Invalid sector size")

  var resPtr: FSInfo
  shallowCopy(resPtr, cast[FSInfo](buffer))
  return resPtr

proc loadFileTable*(path: string, info: FSInfo): (FileTable, TableRef[int, FileTableEntry]) =
  let file = open(path, fmRead)
  file.setFilePos(info.tableAddr * info.bytesPerSector)
  let buffer = alloc(info.bytesPerSector)
  let readLen = file.readBuffer(buffer, info.bytesPerSector)

  defer:
    file.close()
    dealloc(buffer)

  if readLen != 4:
    raise newException(ValueError, "Not enough volume size!")

  let headBuf = alloc(FileTableSize)
  copyMem(headBuf, buffer, FileTableSize)

  var table: FileTable
  shallowCopy(table, cast[FileTable](headBuf))

  dealloc(headBuf)

  let tableBuf = alloc(info.bytesPerSector * (table.extraLength + 1) - 4)

  copyMem(tableBuf, buffer + 4, info.bytesPerSector - 4)

  if table.extraLength != 0:
    let expectedLen = info.bytesPerSector * table.extraLength
    let extraLen = file.readBuffer(tableBuf + (info.bytesPerSector - 4), expectedLen)
    if extraLen != expectedLen:
      dealloc(tableBuf)
      raise newException(ValueError, &"{expectedLen} was expected to read, but {extraLen} was available.")
  
  var ftEntries = newTable[int, FileTableEntry]()

  let po = alloc(FileTableEntrySize)

  for idx in 0..(table.entries - 1):
    copyMem(po, tableBuf + idx * FileTableEntrySize, FileTableEntrySize)
    var entry: FileTableEntry
    shallowCopy(entry, cast[FileTableEntry](po))

    ftEntries.add(entry.id, entry)

  dealloc(po)
  dealloc(tableBuf)

  return (table, ftEntries)

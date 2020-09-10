proc `+`*(po: pointer, offset: int): pointer = cast[pointer](cast[int](po) + offset)

proc `-`*(po: pointer, offset: int): pointer = cast[pointer](cast[int](po) - offset)

OUTPUT_ARCH( "riscv" )
ENTRY( entry_assembly )

MEMORY
{
  RAM(xrw) : ORIGIN = 0x0, LENGTH = 0x40000
}

_estack = ORIGIN(RAM) + LENGTH(RAM);

SECTIONS
{
  .text :
  {
    . = ALIGN(8);
    PROVIDE( entry_assembly = .);
    KEEP( *(.text.entry) )
    *(.text)
      *(.text*)
      *(.rodata)
      *(.rodata*)
      . = ALIGN(8);
    _etext = .;
    _sidata = _etext;
  } >RAM

  .data :
  {
    . = ALIGN(8);
    _sdata = .;
    *(.data)
      *(.data*)
      . = ALIGN(8);
    _edata = .;
  } >RAM

  .bss :
  {
    . = ALIGN(8);
    _sbss = .;
    *(.bss)
      *(.bss*)
      *(COMMON)
      . = ALIGN(8);
    _ebss = .;
  } >RAM

  .heap :
  {
    . = ALIGN(8);
    _heap_start = .;
  } >RAM
}

OUTPUT_ARCH( "riscv" )
ENTRY( reset_vector )

SECTIONS
{
  /* Boot ROM contains only the code needed to initialize DRAM,
     and to authenticate the full boot loader.
     This includes the size and expected hash of the boot loader. */

  /* Boot ROM base */
  . = 0x1000;
  .text : {
    *(.text.entry)
    *(.text.platform)
    *(.text.*)
    *(.text)
    *(.data.*)
    *(.data)
    *(.sdata)
    *(.sdata.*)
    *(.rodata)
    *(.rodata.*)
    *(.srodata)
    *(.srodata.*)
    *(.got)
    *(.got.*)
    . = ALIGN(0x8);
    _end = .;
  }
}

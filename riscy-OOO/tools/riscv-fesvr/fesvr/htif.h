// See LICENSE for license details.

#ifndef __HTIF_H
#define __HTIF_H

#include "memif.h"
#include "syscall.h"
#include "device.h"
#include <string.h>
#include <vector>

// host-target interface.
// Target: riscv processor (or spike).
// Host: x86 host machine to handle stdio etc.

class htif_t
{
 public:
  htif_t(const std::vector<std::string>& target_args);
  virtual ~htif_t();

  virtual void start();
  virtual void stop();

  int run();
  bool done();
  int exit_code(); // the real exit code (shift away bit 0 which is always 1)

  virtual memif_t& memif() { return mem; }

 protected:
  virtual void reset() = 0;

  // read/write_chunk access target's memory
  virtual void read_chunk(addr_t taddr, size_t len, void* dst) = 0;
  virtual void write_chunk(addr_t taddr, size_t len, const void* src) = 0;
  virtual void clear_chunk(addr_t taddr, size_t len);

  virtual size_t chunk_align() = 0;
  virtual size_t chunk_max_size() = 0;

  // copy program binary to target's memory, and find out MMIP addrs for
  // tohost and fromhost
  virtual void load_program();
  virtual void idle() {}

  const std::vector<std::string>& host_args() { return hargs; }

  reg_t get_entry_point() { return entry; }

  // expose for riscy htif
  bcd_t& get_bcd() { return bcd; }
  device_list_t& get_device_list() { return device_list; }
  bool raw_exitcode_nonzero() { return exitcode != 0; }
 public:
  addr_t get_tohost_addr() { return tohost_addr; }
  addr_t get_fromhost_addr() { return fromhost_addr; }

 private:
  memif_t mem;
  reg_t entry;
  bool writezeros;
  std::vector<std::string> hargs; // args for host, e.g. +disk
  std::vector<std::string> targs; // args for target, e.g. bbl
  std::string sig_file;
  addr_t sig_addr; // torture
  addr_t sig_len; // torture
  addr_t tohost_addr; // mtohost MMIO addr
  addr_t fromhost_addr; // mfromhost MMIO addr
  int exitcode; // bit 0 of exitcode should be 1 if target has exited
  bool stopped;

  device_list_t device_list; // syscall_proxy as list[0], bcd as list[1]
  syscall_t syscall_proxy;
  bcd_t bcd;
  std::vector<device_t*> dynamic_devices;

  const std::vector<std::string>& target_args() { return targs; }

  friend class memif_t;
  friend class syscall_t;
};

#endif // __HTIF_H

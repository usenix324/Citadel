#include <stdint.h>
#include <stdbool.h>

#include "platform.h"
/*
  provides types:
  - device_secret_t
  provides functions:
  - void platform_read_device_secret(device_secret_t * out_device_secret)
  - void platform_hide_device_secret()
  - void platform_finalize_secure_boot()
  - void create_random_value(size_t bytes, void * out_random_data)
*/

#include <cryptography.h>
/*
  provides types:
  - hash_t
  - hash_context_t
  - symmetric_key_t
  - symmetric_public_data_t
  - public_key_seed_t
  - public_key_t
  - secret_key_t
  - signature_t
  provides functions:
  - void hash(void * in_data, size_t in_data_size, hash_t * out_hash)
  - void hash_init(hash_context_t * hash_context)
  - void hash_extend(hash_context_t * hash_context)
  - void hash_finalize(hash_context_t * hash_context, hash_t * out_hash)
#  - void symmetric_encrypt(void * in_plaintext, size_t * in_message_size, symmetric_key_t in_key, symmetric_public_data_t * in_public_values, void * out_ciphertext)
#  - void symmetric_decrypt(void * in_ciphertext, size_t * in_message_size, symmetric_key_t in_key, symmetric_public_data_t * in_public_values, void * out_plaintext)
  - void create_secret_signing_key(public_key_seed_t * in_seed, secret_key_t * out_secret_key)
  - void compute_public_signing_key(secret_key_t * in_secret_key, public_key_t * out_public_key)
  - void sign(void * in_data, size_t in_data_size, public_key_t * in_public_key, secret_key_t * in_secret_key, signature_t * out_signature)
*/

// Boot image header is located at the begining of the SM state
boot_image_header_t *boot_image_header = (boot_image_header_t *)SM_STATE_ADDR;

void bootloader() {
  // Prerequisite: platform:
  // - loads the untrusted software into memory
  // - initializes the architecture to a well-known, public, trusted state
  // - initializes any memory relied upon by the bootloader to a trusted state

  // 1). Measure the loaded software
  // The loaded image may (and does) include segments that are excluded from
  // measurement. The measured segment is contiguous (in an enclave-capable
  // system, it is the precisely the security monitor)

  // Perform the measurement
  hash((void *) SM_ADDR, SM_LEN, &(boot_image_header->software_measurement) );

  // 2.a). Derive the device key seed from device secret
  // (SK_D is seeded with the device secret directly)
  _Static_assert ( ( sizeof(device_secret_t) == sizeof(key_seed_t) ), "Device secret is not large enough to serve as input to the KDF");

  key_seed_t device_key_seed;
  platform_read_device_secret( (device_secret_t *) &device_key_seed);
  platform_hide_device_secret();

  // 2.b). Derive the software key seed from the device key seed and the software measurement
  // This ensures the post-boot software's keys are unique to that software's measurement.
  _Static_assert ( ( sizeof(hash_t) >= sizeof(key_seed_t) ), "This implementation requires hash_t to be of a bigger size than key_seed_t.");

  key_seed_t software_key_seed;
  hash_t hash_out;
  hash_context_t hash_scratchpad;
  hash_init(&hash_scratchpad);
  hash_extend( &hash_scratchpad, &device_key_seed, sizeof(device_key_seed) );
  hash_extend( &hash_scratchpad, &(boot_image_header->software_measurement), sizeof(boot_image_header->software_measurement) );
  hash_finalize( &hash_scratchpad, (hash_t *)(&hash_out) );

  for(int i=0; i < LENGTH_SEED; i++) {
    software_key_seed.bytes[i] = hash_out.bytes[i];
  } 

  // 3). Seed a KDF with the device secret to compute the device's secret signing key
  secret_key_t device_secret_signing_key;
  create_secret_signing_key( &device_key_seed, &device_secret_signing_key);

  if ( !boot_image_header->device_public_key_present ) {
    compute_public_signing_key( &device_secret_signing_key, &(boot_image_header->device_public_key) );
    boot_image_header->device_public_key_present = true;
  }

  // 4). Seed a KDF with H(device secret, measurement) to (re)compute the SW's signing key
  create_secret_signing_key(&software_key_seed, &(boot_image_header->software_secret_key) );

  // If the measured software's public key is not marked as present, (re)derive it
  if ( !boot_image_header->software_public_key_present ) {
    compute_public_signing_key( &(boot_image_header->software_secret_key), &(boot_image_header->software_public_key) );
    boot_image_header->software_public_key_present = true;
  }

  // 5). Endorse the measured software by signing H(PK_SW, measurement) with SK_D
  hash_context_t software_digest_context;
  hash_t software_digest;
  hash_init(&software_digest_context);
  hash_extend(&software_digest_context,
    &(boot_image_header->software_public_key),
    sizeof(boot_image_header->software_public_key) );
  hash_extend(&software_digest_context,
    &(boot_image_header->software_measurement),
    sizeof(boot_image_header->software_measurement));
  hash_finalize(&software_digest_context, &software_digest);

  sign( &software_digest,
    sizeof(software_digest),
    &(boot_image_header->device_public_key),
    &device_secret_signing_key,
    &(boot_image_header->software_signature) );

  // ASM postamble cleans sensitive state, wakes all other cores, and boots software
  return;
}

/* Copyright 2009-2011,2013-2015,2018-2019,2023,2024
     Free Software Foundation, Inc.

   This file is part of Guile.

   Guile is free software: you can redistribute it and/or modify it
   under the terms of the GNU Lesser General Public License as published
   by the Free Software Foundation, either version 3 of the License, or
   (at your option) any later version.

   Guile is distributed in the hope that it will be useful, but WITHOUT
   ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
   FITNESS FOR A PARTICULAR PURPOSE.  See the GNU Lesser General Public
   License for more details.

   You should have received a copy of the GNU Lesser General Public
   License along with Guile.  If not, see
   <https://www.gnu.org/licenses/>.  */

#ifdef HAVE_CONFIG_H
# include <config.h>
#endif

#include <assert.h>
#include <intprops.h>
#include <unistd.h>
#include <string.h>
#include <stdio.h>
#include "boolean.h"
#include "bytevectors.h"
#include "chars.h"
#include "eval.h"
#include "extensions.h"
#include "gsubr.h"
#include "modules.h"
#include "numbers.h"
#include "ports-internal.h"
#include "procs.h"
#include "smob.h"
#include "strings.h"
#include "symbols.h"
#include "syscalls.h"
#include "threads.h"
#include "values.h"
#include "variable.h"
#include "vectors.h"
#include "version.h"

#include "r6rs-ports.h"




SCM_SYMBOL (sym_ISO_8859_1, "ISO-8859-1");
SCM_SYMBOL (sym_error, "error");




/* Unimplemented features.  */


/* Transoders are currently not implemented since Guile 1.8 is not
   Unicode-capable.  Thus, most of the code here assumes the use of the
   binary transcoder.  */
static inline void
transcoders_not_implemented (void)
{
  fprintf (stderr, "%s: warning: transcoders not implemented\n",
	   PACKAGE_NAME);
}




/* End-of-file object.  */

SCM_DEFINE (scm_eof_object, "eof-object", 0, 0, 0,
	    (void),
	    "Return the end-of-file object.")
#define FUNC_NAME s_scm_eof_object
{
  return SCM_EOF_VAL;
}
#undef FUNC_NAME




/* Input ports.  */

#define MAX(A, B) ((A) >= (B) ? (A) : (B))
#define MIN(A, B) ((A) < (B) ? (A) : (B))

/* Bytevector input ports.  */
static scm_t_port_type *bytevector_input_port_type = 0;

struct bytevector_input_port {
  SCM bytevector;
  size_t pos;
};

static inline SCM
make_bytevector_input_port (SCM bv)
{
  const unsigned long mode_bits = SCM_RDNG;
  struct bytevector_input_port *stream;

  stream = scm_gc_typed_calloc (struct bytevector_input_port);
  stream->bytevector = bv;
  stream->pos = 0;
  return scm_c_make_port_with_encoding (bytevector_input_port_type, mode_bits,
                                        sym_ISO_8859_1, sym_error,
                                        (scm_t_bits) stream);
}

static size_t
bytevector_input_port_read (SCM port, SCM dst, size_t start, size_t count)
{
  size_t remaining;
  struct bytevector_input_port *stream = (void *) SCM_STREAM (port);

  if (stream->pos >= SCM_BYTEVECTOR_LENGTH (stream->bytevector))
    return 0;

  remaining = SCM_BYTEVECTOR_LENGTH (stream->bytevector) - stream->pos;
  if (remaining < count)
    count = remaining;

  memcpy (SCM_BYTEVECTOR_CONTENTS (dst) + start,
          SCM_BYTEVECTOR_CONTENTS (stream->bytevector) + stream->pos,
          count);

  stream->pos += count;

  return count;
}

static scm_t_off
bytevector_input_port_seek (SCM port, scm_t_off offset, int whence)
#define FUNC_NAME "bytevector_input_port_seek"
{
  struct bytevector_input_port *stream = (void *) SCM_STREAM (port);
  size_t base;
  scm_t_off target;

  if (whence == SEEK_CUR)
    base = stream->pos;
  else if (whence == SEEK_SET)
    base = 0;
  else if (whence == SEEK_END)
    base = SCM_BYTEVECTOR_LENGTH (stream->bytevector);
  else
    scm_wrong_type_arg_msg (FUNC_NAME, 0, port, "invalid `seek' parameter");

  if (base > SCM_T_OFF_MAX
      || INT_ADD_OVERFLOW ((scm_t_off) base, offset))
    scm_num_overflow (FUNC_NAME);
  target = (scm_t_off) base + offset;

  if (target >= 0 && target <= SCM_BYTEVECTOR_LENGTH (stream->bytevector))
    stream->pos = target;
  else
    scm_out_of_range (FUNC_NAME, scm_from_off_t (offset));

  return target;
}
#undef FUNC_NAME


/* Instantiate the bytevector input port type.  */
static inline void
initialize_bytevector_input_ports (void)
{
  bytevector_input_port_type =
    scm_make_port_type ("r6rs-bytevector-input-port",
                        bytevector_input_port_read,
			NULL);

  scm_set_port_seek (bytevector_input_port_type, bytevector_input_port_seek);
}


SCM_DEFINE (scm_open_bytevector_input_port,
	    "open-bytevector-input-port", 1, 1, 0,
	    (SCM bv, SCM transcoder),
	    "Return an input port whose contents are drawn from "
	    "bytevector @var{bv}.")
#define FUNC_NAME s_scm_open_bytevector_input_port
{
  SCM_VALIDATE_BYTEVECTOR (1, bv);
  if (!SCM_UNBNDP (transcoder) && !scm_is_false (transcoder))
    transcoders_not_implemented ();

  return make_bytevector_input_port (bv);
}
#undef FUNC_NAME




/* Binary input.  */

/* We currently don't support specific binary input ports.  */
#define SCM_VALIDATE_BINARY_INPUT_PORT SCM_VALIDATE_OPINPORT

SCM_DEFINE (scm_get_u8, "get-u8", 1, 0, 0,
	    (SCM port),
	    "Read an octet from @var{port}, a binary input port, "
	    "blocking as necessary.")
#define FUNC_NAME s_scm_get_u8
{
  SCM result;
  int c_result;

  SCM_VALIDATE_BINARY_INPUT_PORT (1, port);

  c_result = scm_get_byte_or_eof (port);
  if (c_result == EOF)
    result = SCM_EOF_VAL;
  else
    result = SCM_I_MAKINUM ((unsigned char) c_result);

  return result;
}
#undef FUNC_NAME

SCM_DEFINE (scm_lookahead_u8, "lookahead-u8", 1, 0, 0,
	    (SCM port),
	    "Like @code{get-u8} but does not update @var{port} to "
	    "point past the octet.")
#define FUNC_NAME s_scm_lookahead_u8
{
  int u8;
  SCM result;

  SCM_VALIDATE_BINARY_INPUT_PORT (1, port);

  u8 = scm_peek_byte_or_eof (port);
  if (u8 == EOF)
    result = SCM_EOF_VAL;
  else
    result = SCM_I_MAKINUM ((uint8_t) u8);

  return result;
}
#undef FUNC_NAME

SCM_DEFINE (scm_get_bytevector_n, "get-bytevector-n", 2, 0, 0,
	    (SCM port, SCM count),
	    "Read @var{count} octets from @var{port}, blocking as "
	    "necessary and return a bytevector containing the octets "
	    "read.  If fewer bytes are available, a bytevector smaller "
	    "than @var{count} is returned.")
#define FUNC_NAME s_scm_get_bytevector_n
{
  SCM result;
  size_t c_count;
  size_t c_read;

  SCM_VALIDATE_BINARY_INPUT_PORT (1, port);
  c_count = scm_to_size_t (count);

  result = scm_c_make_bytevector (c_count);

  if (SCM_LIKELY (c_count > 0))
    /* XXX: `scm_c_read ()' does not update the port position.  */
    c_read = scm_c_read_bytes (port, result, 0, c_count);
  else
    /* Don't invoke `scm_c_read ()' since it may block.  */
    c_read = 0;

  if (c_read < c_count)
    {
      if (c_read == 0)
        result = SCM_EOF_VAL;
      else
	result = scm_c_shrink_bytevector (result, c_read);
    }

  return result;
}
#undef FUNC_NAME

SCM_DEFINE (scm_get_bytevector_n_x, "get-bytevector-n!", 4, 0, 0,
	    (SCM port, SCM bv, SCM start, SCM count),
	    "Read @var{count} bytes from @var{port} and store them "
	    "in @var{bv} starting at index @var{start}.  Return either "
	    "the number of bytes actually read or the end-of-file "
	    "object.")
#define FUNC_NAME s_scm_get_bytevector_n_x
{
  SCM result;
  size_t c_start, c_count, c_len;
  size_t c_read;

  SCM_VALIDATE_BINARY_INPUT_PORT (1, port);
  SCM_VALIDATE_BYTEVECTOR (2, bv);
  c_start = scm_to_size_t (start);
  c_count = scm_to_size_t (count);

  c_len = SCM_BYTEVECTOR_LENGTH (bv);

  if (SCM_UNLIKELY (c_len < c_start
                    || (c_len - c_start < c_count)))
    scm_out_of_range (FUNC_NAME, count);

  if (SCM_LIKELY (c_count > 0))
    c_read = scm_c_read_bytes (port, bv, c_start, c_count);
  else
    /* Don't invoke `scm_c_read ()' since it may block.  */
    c_read = 0;

  if (c_read == 0 && c_count > 0)
    result = SCM_EOF_VAL;
  else
    result = scm_from_size_t (c_read);

  return result;
}
#undef FUNC_NAME

SCM_DEFINE (scm_get_bytevector_some, "get-bytevector-some", 1, 0, 0,
	    (SCM port),
            "Read from @var{port}, blocking as necessary, until bytes "
            "are available or an end-of-file is reached.  Return either "
            "the end-of-file object or a new bytevector containing some "
            "of the available bytes (at least one), and update the port "
            "position to point just past these bytes.")
#define FUNC_NAME s_scm_get_bytevector_some
{
  SCM buf;
  size_t cur, avail;
  SCM bv;

  SCM_VALIDATE_BINARY_INPUT_PORT (1, port);

  buf = scm_fill_input (port, 0, &cur, &avail);
  if (avail == 0)
    {
      scm_port_buffer_set_has_eof_p (buf, SCM_BOOL_F);
      return SCM_EOF_VAL;
    }

  bv = scm_c_make_bytevector (avail);
  scm_port_buffer_take (buf, (uint8_t *) SCM_BYTEVECTOR_CONTENTS (bv),
                        avail, cur, avail);

  return bv;
}
#undef FUNC_NAME

SCM_DEFINE (scm_get_bytevector_some_x, "get-bytevector-some!", 4, 0, 0,
	    (SCM port, SCM bv, SCM start, SCM count),
            "Read up to @var{count} bytes from @var{port}, blocking "
            "as necessary until at least one byte is available or an "
            "end-of-file is reached.  Store them in @var{bv} starting "
            "at index @var{start}.  Return the number of bytes actually "
            "read, or an end-of-file object.")
#define FUNC_NAME s_scm_get_bytevector_some_x
{
  SCM buf;
  size_t c_start, c_count, c_len;
  size_t cur, avail, transfer_size;

  SCM_VALIDATE_BINARY_INPUT_PORT (1, port);
  SCM_VALIDATE_BYTEVECTOR (2, bv);
  c_start = scm_to_size_t (start);
  c_count = scm_to_size_t (count);

  c_len = SCM_BYTEVECTOR_LENGTH (bv);

  if (SCM_UNLIKELY (c_len < c_start
                    || c_len - c_start < c_count))
    scm_out_of_range (FUNC_NAME, count);

  if (c_count == 0)
    return SCM_INUM0;

  buf = scm_fill_input (port, 0, &cur, &avail);
  if (avail == 0)
    {
      scm_port_buffer_set_has_eof_p (buf, SCM_BOOL_F);
      return SCM_EOF_VAL;
    }

  transfer_size = MIN (avail, c_count);
  scm_port_buffer_take (buf,
                        (uint8_t *) SCM_BYTEVECTOR_CONTENTS (bv) + c_start,
                        transfer_size, cur, avail);

  return scm_from_size_t (transfer_size);
}
#undef FUNC_NAME

static SCM get_bytevector_all_var;

static void
init_bytevector_io_vars (void)
{
  get_bytevector_all_var =
    scm_c_public_lookup ("ice-9 binary-port", "get-bytevector-all");
}

SCM
scm_get_bytevector_all (SCM port)
{
  static scm_i_pthread_once_t once = SCM_I_PTHREAD_ONCE_INIT;
  scm_i_pthread_once (&once, init_bytevector_io_vars);

  return scm_call_1 (scm_variable_ref (get_bytevector_all_var), port);
}




/* Binary output.  */

/* We currently don't support specific binary input ports.  */
#define SCM_VALIDATE_BINARY_OUTPUT_PORT SCM_VALIDATE_OPOUTPORT


SCM_DEFINE (scm_put_u8, "put-u8", 2, 0, 0,
	    (SCM port, SCM octet),
	    "Write @var{octet} to binary port @var{port}.")
#define FUNC_NAME s_scm_put_u8
{
  uint8_t c_octet;

  SCM_VALIDATE_BINARY_OUTPUT_PORT (1, port);
  c_octet = scm_to_uint8 (octet);

  scm_c_write (port, &c_octet, 1);

  return SCM_UNSPECIFIED;
}
#undef FUNC_NAME

SCM_DEFINE (scm_put_bytevector, "put-bytevector", 2, 2, 0,
	    (SCM port, SCM bv, SCM start, SCM count),
	    "Write the contents of @var{bv} to @var{port}, optionally "
	    "starting at index @var{start} and limiting to @var{count} "
	    "octets.")
#define FUNC_NAME s_scm_put_bytevector
{
  size_t c_start, c_count, c_len;

  SCM_VALIDATE_BINARY_OUTPUT_PORT (1, port);
  SCM_VALIDATE_BYTEVECTOR (2, bv);

  c_len = SCM_BYTEVECTOR_LENGTH (bv);

  if (!scm_is_eq (start, SCM_UNDEFINED))
    {
      c_start = scm_to_size_t (start);
      if (SCM_UNLIKELY (c_start > c_len))
        scm_out_of_range (FUNC_NAME, start);

      if (!scm_is_eq (count, SCM_UNDEFINED))
	{
	  c_count = scm_to_size_t (count);
	  if (SCM_UNLIKELY (c_count > c_len - c_start))
	    scm_out_of_range (FUNC_NAME, count);
	}
      else
        c_count = c_len - c_start;
    }
  else
    c_start = 0, c_count = c_len;

  scm_c_write_bytes (port, bv, c_start, c_count);

  return SCM_UNSPECIFIED;
}
#undef FUNC_NAME

SCM_DEFINE (scm_unget_bytevector, "unget-bytevector", 2, 2, 0,
	    (SCM port, SCM bv, SCM start, SCM count),
	    "Unget the contents of @var{bv} to @var{port}, optionally "
	    "starting at index @var{start} and limiting to @var{count} "
	    "octets.")
#define FUNC_NAME s_scm_unget_bytevector
{
  unsigned char *c_bv;
  size_t c_start, c_count, c_len;

  SCM_VALIDATE_BINARY_INPUT_PORT (1, port);
  SCM_VALIDATE_BYTEVECTOR (2, bv);

  c_len = SCM_BYTEVECTOR_LENGTH (bv);
  c_bv = (unsigned char *) SCM_BYTEVECTOR_CONTENTS (bv);

  if (!scm_is_eq (start, SCM_UNDEFINED))
    {
      c_start = scm_to_size_t (start);
      if (SCM_UNLIKELY (c_start > c_len))
        scm_out_of_range (FUNC_NAME, start);

      if (!scm_is_eq (count, SCM_UNDEFINED))
	{
	  c_count = scm_to_size_t (count);
	  if (SCM_UNLIKELY (c_count > c_len - c_start))
	    scm_out_of_range (FUNC_NAME, count);
	}
      else
        c_count = c_len - c_start;
    }
  else
    c_start = 0, c_count = c_len;

  scm_unget_bytes (c_bv + c_start, c_count, port);

  return SCM_UNSPECIFIED;
}
#undef FUNC_NAME




/* Bytevector output port.  */

/* Implementation of "bytevector output ports".

   Each bytevector output port has an internal buffer, of type
   `scm_t_bytevector_output_port_buffer', attached to it.  The procedure
   returned along with the output port is actually an applicable SMOB.
   The SMOB holds a reference to the port.  When applied, the SMOB
   swallows the port's internal buffer, turning it into a bytevector,
   and resets it.

   XXX: Access to a bytevector output port's internal buffer is not
   thread-safe.  */

static scm_t_port_type *bytevector_output_port_type = 0;

SCM_SMOB (bytevector_output_port_procedure,
	  "r6rs-bytevector-output-port-procedure",
	  0);

#define SCM_GC_BYTEVECTOR_OUTPUT_PORT "r6rs-bytevector-output-port"
#define SCM_BYTEVECTOR_OUTPUT_PORT_BUFFER_INITIAL_SIZE 4096

/* Representation of a bytevector output port's internal buffer.  */
typedef struct
{
  size_t total_len;
  size_t len;
  size_t pos;
  char  *buffer;

  /* The get-bytevector procedure will flush this port, if it's
     open.  */
  SCM port;
} scm_t_bytevector_output_port_buffer;


/* Accessing a bytevector output port's buffer.  */
#define SCM_BYTEVECTOR_OUTPUT_PORT_BUFFER(_port) \
  ((scm_t_bytevector_output_port_buffer *) SCM_STREAM (_port))
#define SCM_SET_BYTEVECTOR_OUTPUT_PORT_BUFFER(_port, _buf) \
  (SCM_SETSTREAM ((_port), (scm_t_bits) (_buf)))


static inline void
bytevector_output_port_buffer_init (scm_t_bytevector_output_port_buffer *buf)
{
  buf->total_len = buf->len = buf->pos = 0;
  buf->buffer = NULL;
  /* Don't clear the port.  */
}

static inline void
bytevector_output_port_buffer_grow (scm_t_bytevector_output_port_buffer *buf,
                                    size_t min_size)
{
  char *new_buf;
  size_t new_size;

  if (buf->buffer)
    {
      if (INT_ADD_OVERFLOW (buf->total_len, buf->total_len))
        scm_num_overflow ("bytevector_output_port_buffer_grow");
      new_size = MAX (min_size, buf->total_len * 2);
      new_buf = scm_gc_realloc ((void *) buf->buffer, buf->total_len,
                                new_size, SCM_GC_BYTEVECTOR_OUTPUT_PORT);
    }
  else
    {
      new_size = MAX (min_size, SCM_BYTEVECTOR_OUTPUT_PORT_BUFFER_INITIAL_SIZE);
      new_buf = scm_gc_malloc_pointerless (new_size,
                                           SCM_GC_BYTEVECTOR_OUTPUT_PORT);
    }

  buf->buffer = new_buf;
  buf->total_len = new_size;
}

static inline SCM
make_bytevector_output_port (void)
{
  SCM port, proc;
  scm_t_bytevector_output_port_buffer *buf;
  const unsigned long mode_bits = SCM_WRTNG;

  buf = (scm_t_bytevector_output_port_buffer *)
    scm_gc_malloc (sizeof (* buf), SCM_GC_BYTEVECTOR_OUTPUT_PORT);
  bytevector_output_port_buffer_init (buf);

  port = scm_c_make_port_with_encoding (bytevector_output_port_type,
                                        mode_bits,
                                        sym_ISO_8859_1, sym_error,
                                        (scm_t_bits)buf);
  buf->port = port;

  SCM_NEWSMOB (proc, bytevector_output_port_procedure, buf);

  return scm_values_2 (port, proc);
}

/* Write octets from WRITE_BUF to the backing store.  */
static size_t
bytevector_output_port_write (SCM port, SCM src, size_t start, size_t count)
#define FUNC_NAME "bytevector_output_port_write"
{
  scm_t_bytevector_output_port_buffer *buf;

  buf = SCM_BYTEVECTOR_OUTPUT_PORT_BUFFER (port);

  if (count > buf->total_len - buf->pos)
    {
      if (INT_ADD_OVERFLOW (buf->pos, count))
        scm_num_overflow (FUNC_NAME);
      bytevector_output_port_buffer_grow (buf, buf->pos + count);
    }

  memcpy (buf->buffer + buf->pos, SCM_BYTEVECTOR_CONTENTS (src) + start, count);

  buf->pos += count;
  buf->len = (buf->len > buf->pos) ? buf->len : buf->pos;

  return count;
}
#undef FUNC_NAME

static scm_t_off
bytevector_output_port_seek (SCM port, scm_t_off offset, int whence)
#define FUNC_NAME "bytevector_output_port_seek"
{
  scm_t_bytevector_output_port_buffer *buf;
  size_t base;
  scm_t_off target;

  buf = SCM_BYTEVECTOR_OUTPUT_PORT_BUFFER (port);

  if (whence == SEEK_CUR)
    base = buf->pos;
  else if (whence == SEEK_SET)
    base = 0;
  else if (whence == SEEK_END)
    base = buf->len;
  else
    scm_wrong_type_arg_msg (FUNC_NAME, 0, port, "invalid `seek' parameter");

  if (base > SCM_T_OFF_MAX
      || INT_ADD_OVERFLOW ((scm_t_off) base, offset))
    scm_num_overflow (FUNC_NAME);
  target = (scm_t_off) base + offset;

  if (target >= 0 && target <= buf->len)
    buf->pos = target;
  else
    scm_out_of_range (FUNC_NAME, scm_from_off_t (offset));

  return target;
}
#undef FUNC_NAME

/* Fetch data from a bytevector output port.  */
SCM_SMOB_APPLY (bytevector_output_port_procedure,
		bytevector_output_port_proc_apply, 0, 0, 0, (SCM proc))
{
  SCM bv;
  scm_t_bytevector_output_port_buffer *buf, result_buf;

  buf = (scm_t_bytevector_output_port_buffer *) SCM_SMOB_DATA (proc);

  if (SCM_OPPORTP (buf->port))
    scm_flush (buf->port);

  result_buf = *buf;
  bytevector_output_port_buffer_init (buf);

  if (result_buf.len == 0)
    bv = scm_c_take_gc_bytevector (NULL, 0, SCM_BOOL_F);
  else
    {
      if (result_buf.total_len > result_buf.len)
	/* Shrink the buffer.  */
	result_buf.buffer = scm_gc_realloc ((void *) result_buf.buffer,
					    result_buf.total_len,
					    result_buf.len,
					    SCM_GC_BYTEVECTOR_OUTPUT_PORT);

      bv = scm_c_take_gc_bytevector ((signed char *) result_buf.buffer,
                                     result_buf.len, SCM_BOOL_F);
    }

  return bv;
}

SCM_DEFINE (scm_open_bytevector_output_port,
	    "open-bytevector-output-port", 0, 1, 0,
	    (SCM transcoder),
	    "Return two values: an output port and a procedure.  The latter "
	    "should be called with zero arguments to obtain a bytevector "
	    "containing the data accumulated by the port.")
#define FUNC_NAME s_scm_open_bytevector_output_port
{
  if (!SCM_UNBNDP (transcoder) && !scm_is_false (transcoder))
    transcoders_not_implemented ();

  return make_bytevector_output_port ();
}
#undef FUNC_NAME

static inline void
initialize_bytevector_output_ports (void)
{
  bytevector_output_port_type =
    scm_make_port_type ("r6rs-bytevector-output-port",
			NULL, bytevector_output_port_write);

  scm_set_port_seek (bytevector_output_port_type, bytevector_output_port_seek);
}




/* Custom ports.  */

static SCM make_custom_binary_input_port_var;
static SCM make_custom_binary_output_port_var;
static SCM make_custom_binary_input_output_port_var;

static scm_i_pthread_once_t make_custom_binary_port_vars =
  SCM_I_PTHREAD_ONCE_INIT;

static void
init_make_custom_binary_port_vars (void)
{
  SCM mod = scm_c_resolve_module ("ice-9 binary-ports");
  SCM iface = scm_module_public_interface (mod);
  make_custom_binary_input_port_var =
    scm_c_module_lookup (iface, "make-custom-binary-input-port");
  make_custom_binary_output_port_var =
    scm_c_module_lookup (iface, "make-custom-binary-output-port");
  make_custom_binary_input_output_port_var =
    scm_c_module_lookup (iface, "make-custom-binary-input/output-port");
}

SCM scm_make_custom_binary_input_port (SCM id, SCM read_proc,
                                       SCM get_position_proc,
                                       SCM set_position_proc, SCM close_proc) {
  scm_i_pthread_once (&make_custom_binary_port_vars,
                      init_make_custom_binary_port_vars);
  return scm_call_5 (scm_variable_ref (make_custom_binary_input_port_var),
                     id, read_proc, get_position_proc, set_position_proc,
                     close_proc);
}

SCM scm_make_custom_binary_output_port (SCM id, SCM write_proc,
                                       SCM get_position_proc,
                                       SCM set_position_proc, SCM close_proc) {
  scm_i_pthread_once (&make_custom_binary_port_vars,
                      init_make_custom_binary_port_vars);
  return scm_call_5 (scm_variable_ref (make_custom_binary_output_port_var),
                     id, write_proc, get_position_proc, set_position_proc,
                     close_proc);
}

SCM scm_make_custom_binary_input_output_port (SCM id, SCM read_proc,
                                              SCM write_proc,
                                              SCM get_position_proc,
                                              SCM set_position_proc,
                                              SCM close_proc) {
  scm_i_pthread_once (&make_custom_binary_port_vars,
                      init_make_custom_binary_port_vars);
  return scm_call_6 (scm_variable_ref (make_custom_binary_input_output_port_var),
                     id, read_proc, write_proc, get_position_proc,
                     set_position_proc, close_proc);
}




/* Transcoded ports.  */

static scm_t_port_type *transcoded_port_type = 0;

#define SCM_TRANSCODED_PORT_BINARY_PORT(_port) SCM_PACK (SCM_STREAM (_port))

static inline SCM
make_transcoded_port (SCM binary_port, unsigned long mode)
{
  return scm_c_make_port (transcoded_port_type, mode,
                          SCM_UNPACK (binary_port));
}

static size_t
transcoded_port_write (SCM port, SCM src, size_t start, size_t count)
{
  SCM bport = SCM_TRANSCODED_PORT_BINARY_PORT (port);
  scm_c_write_bytes (bport, src, start, count);
  return count;
}

static size_t
transcoded_port_read (SCM port, SCM dst, size_t start, size_t count)
{
  SCM bport = SCM_TRANSCODED_PORT_BINARY_PORT (port);
  return scm_c_read_bytes (bport, dst, start, count);
}

static void
transcoded_port_close (SCM port)
{
  scm_close_port (SCM_TRANSCODED_PORT_BINARY_PORT (port));
}

static inline void
initialize_transcoded_ports (void)
{
  transcoded_port_type =
    scm_make_port_type ("r6rs-transcoded-port", transcoded_port_read,
                        transcoded_port_write);
  scm_set_port_close (transcoded_port_type, transcoded_port_close);
  scm_set_port_needs_close_on_gc (transcoded_port_type, 1);
}

SCM_INTERNAL SCM scm_i_make_transcoded_port (SCM);

SCM_DEFINE (scm_i_make_transcoded_port,
	    "%make-transcoded-port", 1, 0, 0,
	    (SCM port),
	    "Return a new port which reads and writes to @var{port}")
#define FUNC_NAME s_scm_i_make_transcoded_port
{
  SCM result;
  unsigned long mode = 0;
  
  SCM_VALIDATE_PORT (SCM_ARG1, port);

  if (scm_is_true (scm_output_port_p (port)))
    mode |= SCM_WRTNG;
  if (scm_is_true (scm_input_port_p (port)))
    mode |= SCM_RDNG;
  
  result = make_transcoded_port (port, mode);

  /* FIXME: We should actually close `port' "in a special way" here,
     according to R6RS.  As there is no way to do that in Guile without
     rendering the underlying port unusable for our purposes as well, we
     just leave it open. */
  
  return result;
}
#undef FUNC_NAME


/* Textual I/O */

SCM_DEFINE (scm_get_string_n_x,
            "get-string-n!", 4, 0, 0,
            (SCM port, SCM str, SCM start, SCM count),
            "Read up to @var{count} characters from @var{port} into "
            "@var{str}, starting at @var{start}.  If no characters "
            "can be read before the end of file is encountered, the end "
            "of file object is returned.  Otherwise, the number of "
            "characters read is returned.")
#define FUNC_NAME s_scm_get_string_n_x
{
  size_t c_start, c_count, c_len, c_end, j;
  scm_t_wchar c;

  SCM_VALIDATE_OPINPORT (1, port);
  SCM_VALIDATE_STRING (2, str);
  c_len = scm_c_string_length (str);
  c_start = scm_to_size_t (start);
  c_count = scm_to_size_t (count);
  c_end = c_start + c_count;

  if (SCM_UNLIKELY (c_end > c_len))
    scm_out_of_range (FUNC_NAME, count);

  for (j = c_start; j < c_end; j++)
    {
      c = scm_getc (port);
      if (c == EOF)
        {
          size_t chars_read = j - c_start;
          return chars_read == 0 ? SCM_EOF_VAL : scm_from_size_t (chars_read);
        }
      scm_c_string_set_x (str, j, SCM_MAKE_CHAR (c));
    }
  return count;
}
#undef FUNC_NAME


/* Initialization.  */

void
scm_register_r6rs_ports (void)
{
  scm_c_register_extension ("libguile-" SCM_EFFECTIVE_VERSION,
                            "scm_init_r6rs_ports",
			    (scm_t_extension_init_func) scm_init_r6rs_ports,
			    NULL);

  initialize_bytevector_input_ports ();
  initialize_bytevector_output_ports ();
  initialize_transcoded_ports ();
}

void
scm_init_r6rs_ports (void)
{
#include "r6rs-ports.x"
}

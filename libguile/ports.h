/* classes: h_files */

#ifndef SCM_PORTS_H
#define SCM_PORTS_H

/* Copyright (C) 1995, 1996, 1997, 1998, 1999, 2000, 2001, 2003, 2004,
 *   2006, 2008, 2009, 2010, 2011, 2012, 2013, 2014 Free Software Foundation, Inc.
 *
 * This library is free software; you can redistribute it and/or
 * modify it under the terms of the GNU Lesser General Public License
 * as published by the Free Software Foundation; either version 3 of
 * the License, or (at your option) any later version.
 *
 * This library is distributed in the hope that it will be useful, but
 * WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the GNU
 * Lesser General Public License for more details.
 *
 * You should have received a copy of the GNU Lesser General Public
 * License along with this library; if not, write to the Free Software
 * Foundation, Inc., 51 Franklin Street, Fifth Floor, Boston, MA
 * 02110-1301 USA
 */



#include "libguile/__scm.h"

#include <stdio.h>
#include <string.h>
#include <unistd.h>
#include "libguile/bytevectors.h"
#include "libguile/gc.h"
#include "libguile/tags.h"
#include "libguile/error.h"
#include "libguile/print.h"
#include "libguile/struct.h"
#include "libguile/threads.h"
#include "libguile/strings.h"
#include "libguile/vectors.h"



/* An internal-only structure defined in ports-internal.h. */
struct scm_port_internal;

/* Port buffers.

   It's important to avoid calling into the kernel too many times.  For
   that reason we buffer the input and output, using "port buffer"
   objects.  Port buffers are represented as vectors containing the
   buffer, two cursors, and a flag.  The bytes in a read buffer are laid
   out like this:

                    |already read | not yet | invalid
                    |    data     |  read   |  data
      readbuf: #vu8(|r r r r r r r|u u u u u|x x x x x|)
               ^buf               ^cur      ^end      ^size(buf)

   Similarly for a write buffer:

                     |already written | not yet | invalid
                     |    data        | written |  data
      writebuf: #vu8(|w w w w w w w w |u u u u u|x x x x x|)
                ^buf                  ^cur      ^end      ^size(buf)

   We use the same port buffer data structure for both purposes.  Port
   buffers are implemented as their own object so that they can be
   atomically swapped in or out of ports, and as Scheme vectors so they
   can be manipulated from Scheme.  */

enum scm_port_buffer_field {
  SCM_PORT_BUFFER_FIELD_BYTEVECTOR,
  SCM_PORT_BUFFER_FIELD_CUR,
  SCM_PORT_BUFFER_FIELD_END,
  SCM_PORT_BUFFER_FIELD_HAS_EOF_P,
  SCM_PORT_BUFFER_FIELD_COUNT
};

/* C representation of a Scheme port.  */

typedef struct 
{
  /* Link back to the port object.  */
  SCM port;

  /* Pointer to internal-only port structure. */
  struct scm_port_internal *internal;

  /* Data for the underlying port implementation as a raw C value.  */
  scm_t_bits stream;

  /* Source location information.  */
  SCM file_name;
  long line_number;
  int column_number;

  /* Port buffers.  */
  SCM read_buf;
  SCM write_buf;

  /* All ports have read and write buffers; an unbuffered port simply
     has a one-byte buffer.  However unreading bytes can expand the read
     buffer, but that doesn't mean that we want to increase the input
     buffering.  For that reason `read_buffering' is a separate
     indication of how many characters to buffer on the read side.
     There isn't a write_buf_size because there isn't an
     `unwrite-byte'.  */
  size_t read_buffering;

  /* True if the port is random access.  Implies that the buffers must
     be flushed before switching between reading and writing, seeking,
     and so on.  */
  int rw_random;

  /* Character encoding support.  */
  SCM encoding;  /* A symbol of upper-case ASCII.  */
  SCM conversion_strategy; /* A symbol; either substitute, error, or escape.  */
} scm_t_port;


SCM_INTERNAL SCM scm_i_port_weak_set;




#define SCM_EOF_OBJECT_P(x) (scm_is_eq ((x), SCM_EOF_VAL))

/* PORT FLAGS
 * A set of flags characterizes a port.
 * Note that we reserve the bits 1 << 24 and above for use by the
 * routines in the port's scm_ptobfuns structure.
 */
#define SCM_OPN		(1L<<16) /* Is the port open? */
#define SCM_RDNG	(2L<<16) /* Is it a readable port? */
#define SCM_WRTNG	(4L<<16) /* Is it writable? */
#define SCM_BUF0	(8L<<16) /* Is it unbuffered? */
#define SCM_BUFLINE     (64L<<16) /* Is it line-buffered? */

#define SCM_PORTP(x) (SCM_HAS_TYP7 (x, scm_tc7_port))
#define SCM_OPPORTP(x) (SCM_PORTP (x) && (SCM_CELL_WORD_0 (x) & SCM_OPN))
#define SCM_INPUT_PORT_P(x) (SCM_PORTP (x) && (SCM_CELL_WORD_0 (x) & SCM_RDNG))
#define SCM_OUTPUT_PORT_P(x) (SCM_PORTP (x) && (SCM_CELL_WORD_0 (x) & SCM_WRTNG))
#define SCM_OPINPORTP(x) (SCM_OPPORTP (x) && SCM_INPUT_PORT_P (x))
#define SCM_OPOUTPORTP(x) (SCM_OPPORTP (x) && SCM_OUTPUT_PORT_P (x))
#define SCM_OPENP(x) (SCM_OPPORTP (x))
#define SCM_CLOSEDP(x) (!SCM_OPENP (x))
#define SCM_CLR_PORT_OPEN_FLAG(p) \
  SCM_SET_CELL_WORD_0 ((p), SCM_CELL_WORD_0 (p) & ~SCM_OPN)

#define SCM_PTAB_ENTRY(x)         ((scm_t_port *) SCM_CELL_WORD_1 (x))
#define SCM_PORT_DESCRIPTOR(port) ((scm_t_ptob_descriptor *) SCM_CELL_WORD_2 (port))
#define SCM_SETPTAB_ENTRY(x, ent)  (SCM_SET_CELL_WORD_1 ((x), (scm_t_bits) (ent)))
#define SCM_STREAM(x)             (SCM_PTAB_ENTRY(x)->stream)
#define SCM_SETSTREAM(x, s)        (SCM_PTAB_ENTRY(x)->stream = (scm_t_bits) (s))
#define SCM_FILENAME(x)           (SCM_PTAB_ENTRY(x)->file_name)
#define SCM_SET_FILENAME(x, n)    (SCM_PTAB_ENTRY(x)->file_name = (n))
#define SCM_LINUM(x)              (SCM_PTAB_ENTRY(x)->line_number)
#define SCM_COL(x)                (SCM_PTAB_ENTRY(x)->column_number)

#define SCM_INCLINE(port)  	do {SCM_LINUM (port) += 1; SCM_COL (port) = 0;} while (0)
#define SCM_ZEROCOL(port)  	do {SCM_COL (port) = 0;} while (0)
#define SCM_INCCOL(port)  	do {SCM_COL (port) += 1;} while (0)
#define SCM_DECCOL(port)  	do {if (SCM_COL (port) > 0) SCM_COL (port) -= 1;} while (0)
#define SCM_TABCOL(port)  	do {SCM_COL (port) += 8 - SCM_COL (port) % 8;} while (0)

/* Maximum number of port types.  */
#define SCM_I_MAX_PORT_TYPE_COUNT  256



typedef enum scm_t_port_type_flags {
  /* Indicates that the port should be closed if it is garbage collected
     while it is open.  */
  SCM_PORT_TYPE_NEEDS_CLOSE_ON_GC = 1 << 0
} scm_t_port_type_flags;

/* port-type description.  */
typedef struct scm_t_ptob_descriptor
{
  char *name;
  int (*print) (SCM exp, SCM port, scm_print_state *pstate);

  size_t (*c_read) (SCM port, SCM dst, size_t start, size_t count);
  size_t (*c_write) (SCM port, SCM src, size_t start, size_t count);
  SCM scm_read;
  SCM scm_write;

  scm_t_off (*seek) (SCM port, scm_t_off OFFSET, int WHENCE);
  void (*close) (SCM port);

  void (*get_natural_buffer_sizes) (SCM port, size_t *read_size,
                                    size_t *write_size);

  int (*input_waiting) (SCM port);

  void (*truncate) (SCM port, scm_t_off length);

  unsigned flags;
} scm_t_ptob_descriptor;

#define SCM_TC2PTOBNUM(x) (0x0ff & ((x) >> 8))
#define SCM_PTOBNUM(x) (SCM_TC2PTOBNUM (SCM_CELL_TYPE (x)))
/* SCM_PTOBNAME can be 0 if name is missing */
#define SCM_PTOBNAME(ptobnum) (scm_c_port_type_ref (ptobnum)->name)

/* Port types, and their vtables.  */
SCM_INTERNAL long scm_c_num_port_types (void);
SCM_API scm_t_ptob_descriptor* scm_c_port_type_ref (long ptobnum);
SCM_API long scm_c_port_type_add_x (scm_t_ptob_descriptor *desc);
SCM_API scm_t_bits scm_make_port_type
	(char *name,
         size_t (*read) (SCM port, SCM dst, size_t start, size_t count),
         size_t (*write) (SCM port, SCM src, size_t start, size_t count));
SCM_API void scm_set_port_scm_read (scm_t_bits tc, SCM read);
SCM_API void scm_set_port_scm_write (scm_t_bits tc, SCM write);
SCM_API void scm_set_port_print (scm_t_bits tc,
				 int (*print) (SCM exp,
					       SCM port,
					       scm_print_state *pstate));
SCM_API void scm_set_port_close (scm_t_bits tc, void (*close) (SCM));
SCM_API void scm_set_port_needs_close_on_gc (scm_t_bits tc, int needs_close_p);
SCM_API void scm_set_port_seek (scm_t_bits tc,
				scm_t_off (*seek) (SCM port,
						   scm_t_off OFFSET,
						   int WHENCE));
SCM_API void scm_set_port_truncate (scm_t_bits tc,
				    void (*truncate) (SCM port,
						      scm_t_off length));
SCM_API void scm_set_port_input_waiting (scm_t_bits tc, int (*input_waiting) (SCM));
SCM_API void scm_set_port_get_natural_buffer_sizes
  (scm_t_bits tc, void (*get_natural_buffer_sizes) (SCM, size_t *, size_t *));

/* The input, output, error, and load ports.  */
SCM_API SCM scm_current_input_port (void);
SCM_API SCM scm_current_output_port (void);
SCM_API SCM scm_current_error_port (void);
SCM_API SCM scm_current_warning_port (void);
SCM_API SCM scm_current_load_port (void);
SCM_API SCM scm_set_current_input_port (SCM port);
SCM_API SCM scm_set_current_output_port (SCM port);
SCM_API SCM scm_set_current_error_port (SCM port);
SCM_API SCM scm_set_current_warning_port (SCM port);
SCM_API void scm_dynwind_current_input_port (SCM port);
SCM_API void scm_dynwind_current_output_port (SCM port);
SCM_API void scm_dynwind_current_error_port (SCM port);
SCM_INTERNAL void scm_i_dynwind_current_load_port (SCM port);

/* Port buffers.  */
SCM_INTERNAL SCM scm_c_make_port_buffer (size_t size);

/* Mode bits.  */
SCM_INTERNAL long scm_i_mode_bits (SCM modes);
SCM_API long scm_mode_bits (char *modes);
SCM_API SCM scm_port_mode (SCM port);

/* Low-level constructors.  */
SCM_API SCM scm_c_make_port_with_encoding (scm_t_bits tag,
                                           unsigned long mode_bits,
                                           SCM encoding,
                                           SCM conversion_strategy,
                                           scm_t_bits stream);
SCM_API SCM scm_c_make_port (scm_t_bits tag, unsigned long mode_bits,
                             scm_t_bits stream);
SCM_API SCM scm_new_port_table_entry (scm_t_bits tag);

/* Predicates.  */
SCM_API SCM scm_port_p (SCM x);
SCM_API SCM scm_input_port_p (SCM x);
SCM_API SCM scm_output_port_p (SCM x);
SCM_API SCM scm_port_closed_p (SCM port);
SCM_API SCM scm_eof_object_p (SCM x);

/* Closing ports.  */
SCM_API SCM scm_close_port (SCM port);
SCM_API SCM scm_close_input_port (SCM port);
SCM_API SCM scm_close_output_port (SCM port);

/* Encoding characters to byte streams, and decoding byte streams to
   characters.  */
SCM_INTERNAL scm_t_string_failed_conversion_handler
scm_i_string_failed_conversion_handler (SCM conversion_strategy);
SCM_INTERNAL SCM scm_i_default_port_encoding (void);
SCM_INTERNAL void scm_i_set_default_port_encoding (const char *encoding);
SCM_INTERNAL SCM scm_i_default_port_conversion_strategy (void);
SCM_INTERNAL void scm_i_set_default_port_conversion_strategy (SCM strategy);
SCM_INTERNAL void scm_i_set_port_encoding_x (SCM port, const char *str);
SCM_API SCM scm_port_encoding (SCM port);
SCM_API SCM scm_set_port_encoding_x (SCM port, SCM encoding);
SCM_API SCM scm_port_conversion_strategy (SCM port);
SCM_API SCM scm_set_port_conversion_strategy_x (SCM port, SCM behavior);

/* Input.  */
SCM_API int scm_get_byte_or_eof (SCM port);
SCM_API int scm_peek_byte_or_eof (SCM port);
SCM_API size_t scm_c_read (SCM port, void *buffer, size_t size);
SCM_API size_t scm_c_read_bytes (SCM port, SCM dst, size_t start, size_t count);
SCM_API scm_t_wchar scm_getc (SCM port);
SCM_API SCM scm_read_char (SCM port);

/* Pushback.  */
SCM_API void scm_unget_bytes (const unsigned char *buf, size_t len, SCM port);
SCM_API void scm_unget_byte (int c, SCM port);
SCM_API void scm_ungetc (scm_t_wchar c, SCM port);
SCM_API void scm_ungets (const char *s, int n, SCM port);
SCM_API SCM scm_peek_char (SCM port);
SCM_API SCM scm_unread_char (SCM cobj, SCM port);
SCM_API SCM scm_unread_string (SCM str, SCM port);

/* Manipulating the buffers.  */
SCM_API SCM scm_setvbuf (SCM port, SCM mode, SCM size);
SCM_API SCM scm_fill_input (SCM port, size_t minimum_size);
SCM_INTERNAL size_t scm_take_from_input_buffers (SCM port, char *dest, size_t read_len);
SCM_API SCM scm_drain_input (SCM port);
SCM_API void scm_end_input (SCM port);
SCM_API SCM scm_force_output (SCM port);
SCM_API void scm_flush (SCM port);

SCM_INTERNAL SCM scm_port_random_access_p (SCM port);
SCM_INTERNAL SCM scm_port_read_buffering (SCM port);
SCM_INTERNAL SCM scm_set_port_read_buffer_x (SCM port, SCM buf);
SCM_INTERNAL SCM scm_port_read (SCM port);
SCM_INTERNAL SCM scm_port_write (SCM port);
SCM_INTERNAL SCM scm_port_read_buffer (SCM port);
SCM_INTERNAL SCM scm_port_write_buffer (SCM port);

/* Output.  */
SCM_API void scm_putc (char c, SCM port);
SCM_API void scm_puts (const char *str_data, SCM port);
SCM_API void scm_c_write (SCM port, const void *buffer, size_t size);
SCM_API void scm_c_write_bytes (SCM port, SCM src, size_t start, size_t count);
SCM_API void scm_lfwrite (const char *ptr, size_t size, SCM port);
SCM_INTERNAL void scm_lfwrite_substr (SCM str, size_t start, size_t end,
				      SCM port);

/* Querying and setting positions, and character availability.  */
SCM_API SCM scm_char_ready_p (SCM port);
SCM_API SCM scm_seek (SCM object, SCM offset, SCM whence);
SCM_API SCM scm_truncate_file (SCM object, SCM length);
SCM_API SCM scm_port_line (SCM port);
SCM_API SCM scm_set_port_line_x (SCM port, SCM line);
SCM_API SCM scm_port_column (SCM port);
SCM_API SCM scm_set_port_column_x (SCM port, SCM line);
SCM_API SCM scm_port_filename (SCM port);
SCM_API SCM scm_set_port_filename_x (SCM port, SCM filename);

/* Port properties.  */
SCM_INTERNAL SCM scm_i_port_property (SCM port, SCM key);
SCM_INTERNAL SCM scm_i_set_port_property_x (SCM port, SCM key, SCM value);

/* Implementation helpers for port printing functions.  */
SCM_API int scm_port_print (SCM exp, SCM port, scm_print_state *);
SCM_API void scm_print_port_mode (SCM exp, SCM port);

/* Iterating over all ports.  */
SCM_API SCM scm_port_for_each (SCM proc);
SCM_API void scm_c_port_for_each (void (*proc)(void *data, SCM p), void *data);
SCM_API SCM scm_flush_all_ports (void);

/* Void ports.  */
SCM_API SCM scm_void_port (char * mode_str);
SCM_API SCM scm_sys_make_void_port (SCM mode);

/* Initialization.  */
SCM_INTERNAL void scm_init_ports (void);


#endif  /* SCM_PORTS_H */

/*
  Local Variables:
  c-file-style: "gnu"
  End:
*/

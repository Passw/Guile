/*	Copyright (C) 1995,1996 Free Software Foundation, Inc.
 * 
 * This program is free software; you can redistribute it and/or modify
 * it under the terms of the GNU General Public License as published by
 * the Free Software Foundation; either version 2, or (at your option)
 * any later version.
 * 
 * This program is distributed in the hope that it will be useful,
 * but WITHOUT ANY WARRANTY; without even the implied warranty of
 * MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
 * GNU General Public License for more details.
 * 
 * You should have received a copy of the GNU General Public License
 * along with this software; see the file COPYING.  If not, write to
 * the Free Software Foundation, 675 Mass Ave, Cambridge, MA 02139, USA.
 *
 * As a special exception, the Free Software Foundation gives permission
 * for additional uses of the text contained in its release of GUILE.
 *
 * The exception is that, if you link the GUILE library with other files
 * to produce an executable, this does not by itself cause the
 * resulting executable to be covered by the GNU General Public License.
 * Your use of that executable is in no way restricted on account of
 * linking the GUILE library code into it.
 *
 * This exception does not however invalidate any other reasons why
 * the executable file might be covered by the GNU General Public License.
 *
 * This exception applies only to the code released by the
 * Free Software Foundation under the name GUILE.  If you copy
 * code from other Free Software Foundation releases into a copy of
 * GUILE, as the General Public License permits, the exception does
 * not apply to the code that you add in this way.  To avoid misleading
 * anyone as to the status of such modified files, you must delete
 * this exception notice from them.
 *
 * If you write modifications of your own for GUILE, it is your choice
 * whether to permit this exception to apply to your modifications.
 * If you do not wish that, delete this exception notice.  
 */


#include <stdio.h>
#include "_scm.h"

#ifdef HAVE_UNISTD_H
#include <unistd.h>
#endif



/* {Errors and Exceptional Conditions}
 */

SCM system_error_sym;

/* True between SCM_DEFER_INTS and SCM_ALLOW_INTS, and
 * when the interpreter is not running at all.
 */
int scm_ints_disabled = 1;


extern int errno;
#ifdef __STDC__
static void 
err_head (char *str)
#else
static void 
err_head (str)
     char *str;
#endif
{
  int oerrno = errno;
  if (SCM_NIMP (scm_cur_outp))
    scm_fflush (scm_cur_outp);
  scm_gen_putc ('\n', scm_cur_errp);
#if 0
  if (SCM_BOOL_F != *scm_loc_loadpath)
    {
      scm_iprin1 (*scm_loc_loadpath, scm_cur_errp, 1);
      scm_gen_puts (scm_regular_string, ", line ", scm_cur_errp);
      scm_intprint ((long) scm_linum, 10, scm_cur_errp);
      scm_gen_puts (scm_regular_string, ": ", scm_cur_errp);
    }
#endif
  scm_fflush (scm_cur_errp);
  errno = oerrno;
  if (scm_cur_errp == scm_def_errp)
    {
      if (errno > 0)
	perror (str);
      fflush (stderr);
      return;
    }
}


SCM_PROC(s_errno, "errno", 0, 1, 0, scm_errno);
#ifdef __STDC__
SCM 
scm_errno (SCM arg)
#else
SCM 
scm_errno (arg)
     SCM arg;
#endif
{
  int old = errno;
  if (!SCM_UNBNDP (arg))
    {
      if (SCM_FALSEP (arg))
	errno = 0;
      else
	errno = SCM_INUM (arg);
    }
  return SCM_MAKINUM (old);
}

SCM_PROC(s_perror, "perror", 1, 0, 0, scm_perror);
#ifdef __STDC__
SCM 
scm_perror (SCM arg)
#else
SCM 
scm_perror (arg)
     SCM arg;
#endif
{
  SCM_ASSERT (SCM_NIMP (arg) && SCM_STRINGP (arg), arg, SCM_ARG1, s_perror);
  err_head (SCM_CHARS (arg));
  return SCM_UNSPECIFIED;
}


#ifdef __STDC__
void 
scm_everr (SCM exp, SCM env, SCM arg, char *pos, char *s_subr)
#else
void 
scm_everr (exp, env, arg, pos, s_subr)
     SCM exp;
     SCM env;
     SCM arg; 
     char *pos;
     char *s_subr;
#endif
{
  SCM desc;
  SCM args;
  
  if ((~0x1fL) & (long) pos)
    desc = scm_makfrom0str (pos);
  else
    desc = SCM_MAKINUM ((long)pos);
  
  {
    SCM sym;
    if (!s_subr || !*s_subr)
      sym = SCM_BOOL_F;
    else
      sym = SCM_CAR (scm_intern0 (s_subr));
    args = scm_listify (desc, sym, arg, SCM_UNDEFINED);
  }
  
  /* (throw (quote %%system-error) <desc> <proc-name> arg)
   *
   * <desc> is a string or an integer (see %%system-errors).
   * <proc-name> is a symbol or #f in some annoying cases (e.g. cddr).
   */
  
  scm_ithrow (system_error_sym, args, 1);
  
  /* No return, but just in case: */

  write (2, "unhandled system error", sizeof ("unhandled system error") - 1);
  exit (1);
}

#ifdef __STDC__
SCM
scm_wta (SCM arg, char *pos, char *s_subr)
#else
SCM
scm_wta (arg, pos, s_subr)
     SCM arg;
     char *pos;
     char *s_subr;
#endif
{
  scm_everr (SCM_UNDEFINED, SCM_EOL, arg, pos, s_subr);
  return SCM_UNSPECIFIED;
}

void (*scm_error_callback) () = 0;

void
scm_error (key, subr, message, args, rest)
     SCM key;
     char *subr;
     char *message;
     SCM args;
     SCM rest;
{
  SCM arg_list;
  if (scm_error_callback)
    (*scm_error_callback) (key, subr, message, args, rest);

  arg_list = scm_listify (scm_makfrom0str (subr),
			  scm_makfrom0str (message),
			  args,
			  rest,
			  SCM_UNDEFINED);
  scm_ithrow (key, arg_list, 1);
  
  /* No return, but just in case: */

  write (2, "unhandled system error", sizeof ("unhandled system error") - 1);
  exit (1);
}

#ifdef __STDC__
void
scm_init_error (void)
#else
void
scm_init_error ()
#endif
{
  system_error_sym = scm_permanent_object (SCM_CAR (scm_intern0 ("%%system-error")));
#include "error.x"
}


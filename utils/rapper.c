/* -*- Mode: c; c-basic-offset: 2 -*-
 *
 * rdfdump.c - Rapier RDF Parser example code 
 *
 * $Id$
 *
 * Copyright (C) 2000-2001 David Beckett - http://purl.org/net/dajobe/
 * Institute for Learning and Research Technology - http://www.ilrt.org/
 * University of Bristol - http://www.bristol.ac.uk/
 * 
 * This package is Free Software or Open Source available under the
 * following licenses (these are alternatives):
 *   1. GNU Lesser General Public License (LGPL)
 *   2. GNU General Public License (GPL)
 *   3. Mozilla Public License (MPL)
 * 
 * See LICENSE.html or LICENSE.txt at the top of this package for the
 * full license terms.
 * 
 */


#ifdef HAVE_CONFIG_H
#include <config.h>
#endif

#include <stdio.h>
#include <string.h>
#ifdef HAVE_GETOPT_H
#include <getopt.h>
#endif

#ifdef LIBRDF_INTERNAL
#include <librdf.h>
#endif

#include <rapier.h>

#ifdef NEED_OPTIND_DECLARATION
extern int optind;
#endif

static void print_statements(void *user_data, const rapier_statement *statement);
int main(int argc, char *argv[]);


/* replace newlines in literal string output with spaces */
static int replace_newlines=0;

/* extra noise? */
static int quiet=0;

static int statement_count=0;


static
void print_statements(void *user_data, const rapier_statement *statement) 
{
  fputs("rdfdump: Statement: ", stdout);

  /* replace newlines with spaces if object is a literal string */
  if(replace_newlines && 
     statement->object_type == RAPIER_OBJECT_TYPE_LITERAL) {
    char *s;
    for(s=(char*)statement->object; *s; s++)
      if(*s == '\n')
        *s=' ';
  }

  rapier_print_statement(statement, stdout);
  fputc('\n', stdout);

  statement_count++;
}


#ifdef HAVE_GETOPT_LONG
#define HELP_TEXT(short, long, description) "  -" #short ", --" #long "  " description "\n"
#else
#define HELP_TEXT(short, long, description) "  -" #short "  " description "\n"
#endif


#define GETOPT_STRING "shrq"

#ifdef HAVE_GETOPT_LONG
static struct option long_options[] =
{
  /* name, has_arg, flag, val */
  {"scan", 0, 0, 's'},
  {"help", 0, 0, 'h'},
  {"replace-newlines", 0, 0, 'r'},
  {"quiet", 0, 0, 'q'},
  {NULL, 0, 0, 0}
};
#endif



int
main(int argc, char *argv[]) 
{
  rapier_parser* parser;
  char *uri_string;
  char *base_uri_string;
  char *program=argv[0];
  int rc;
  int scanning=0;
  int usage=0;
#ifdef LIBRDF_INTERNAL
  librdf_uri *base_uri;
  librdf_uri *uri;
#else
  const char *base_uri;
  const char *uri;
#endif

#ifdef LIBRDF_INTERNAL
  librdf_init_world(NULL, NULL);
#endif

  
  while (!usage)
  {
    int c;
#ifdef HAVE_GETOPT_LONG
    int option_index = 0;

    c = getopt_long (argc, argv, GETOPT_STRING, long_options, &option_index);
#else
    c = getopt (argc, argv, GETOPT_STRING);
#endif
    if (c == -1)
      break;

    switch (c) {
      case 0:
      case '?': /* getopt() - unknown option */
#ifdef HAVE_GETOPT_LONG
        fprintf(stderr, "Unknown option %s\n", long_options[option_index].name);
#else
        fprintf(stderr, "Unknown option %s\n", argv[optind]);
#endif
        usage=2; /* usage and error */
        break;
        
      case 'h':
        usage=1;
        break;

      case 's':
        scanning=1;
        break;

      case 'q':
        quiet=1;
        break;

      case 'r':
        replace_newlines=1;
        break;
    }
    
  }

  if(optind != argc-1 && optind != argc-2)
    usage=2; /* usage and error */
  

  if(usage) {
    fprintf(stderr, "Usage: %s [OPTIONS] <source file: URI> [base URI]\n", program);
    fprintf(stderr, "Parse the given file as RDF using Rapier\n");
    fprintf(stderr, HELP_TEXT(h, help, "This message"));
    fprintf(stderr, HELP_TEXT(s, scan, "Scan for <rdf:RDF> element in source"));
    fprintf(stderr, HELP_TEXT(r, replace-newlines, "Replace newlines with spaces in literals"));
    fprintf(stderr, HELP_TEXT(q, quiet, "No extra information messages"));
    return(usage>1);
  }


  if(optind == argc-1)
    uri_string=base_uri_string=argv[optind];
  else {
    uri_string=argv[optind++];
    base_uri_string=argv[optind];
  }
  

#ifdef LIBRDF_INTERNAL
  base_uri=librdf_new_uri(base_uri_string);
  if(!base_uri) {
    fprintf(stderr, "%s: Failed to create librdf_uri for %s\n",
            program, uri);
    return(1);
  }
  uri=librdf_new_uri(uri_string);
  if(!uri) {
    fprintf(stderr, "%s: Failed to create librdf_uri for %s\n",
            program, uri);
    return(1);
  }
#else
  uri=uri_string;
  base_uri=base_uri_string;
#endif
  
  parser=rapier_new();
  if(!parser) {
    fprintf(stderr, "%s: Failed to create rapier parser\n", program);
    return(1);
  }


  if(scanning)
    rapier_set_feature(parser, RAPIER_FEATURE_SCANNING, 1);
  

  /* PARSE the URI as RDF/XML */
  if(!quiet) {
    if(base_uri_string)
      fprintf(stdout, "%s: Parsing URI %s with base URI %s\n", program,
              uri_string, base_uri_string);
    else
      fprintf(stdout, "%s: Parsing URI %s\n", program, uri_string);
  }
  
  rapier_set_statement_handler(parser, NULL, print_statements);


  if(rapier_parse_file(parser, uri, base_uri)) {
    fprintf(stderr, "%s: Failed to parse RDF into model\n", program);
    rc=1;
  } else
    rc=0;
  rapier_free(parser);

  fprintf(stdout, "%s: Parsing returned %d statements\n", program,
          statement_count);

#ifdef LIBRDF_INTERNAL
  librdf_free_uri(base_uri);

  librdf_destroy_world();
#endif

  return(rc);
}

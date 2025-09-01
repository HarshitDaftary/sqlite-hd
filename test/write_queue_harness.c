/* Minimal harness to exercise PRAGMA write_queue across two connections. */
#include "sqlite3.h"
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

static int get_int_pragma(sqlite3 *db, const char *sql){
  sqlite3_stmt *stmt = 0; int rc = sqlite3_prepare_v2(db, sql, -1, &stmt, 0);
  if(rc!=SQLITE_OK){ fprintf(stderr,"prepare failed: %s\n", sqlite3_errmsg(db)); return -9999; }
  rc = sqlite3_step(stmt);
  int val = (rc==SQLITE_ROW)? sqlite3_column_int(stmt,0) : -8888;
  sqlite3_finalize(stmt);
  return val;
}

static void exec_or_die(sqlite3 *db, const char *sql){
  char *err=0; int rc = sqlite3_exec(db, sql, 0, 0, &err);
  if(rc!=SQLITE_OK){ fprintf(stderr,"exec error (%d) %s on: %s\n", rc, err?err:"", sql); sqlite3_free(err); exit(1);} }

int main(void){
  sqlite3 *db1=0,*db2=0; int rc;
  rc = sqlite3_open("wqtest.db", &db1); if(rc) return 2;
  rc = sqlite3_open("wqtest.db", &db2); if(rc) return 3;

  int v1 = get_int_pragma(db1, "PRAGMA write_queue;");
  int v2 = get_int_pragma(db2, "PRAGMA write_queue;");
  printf("initial:%d,%d\n", v1, v2);
  if(v1!=1 || v2!=1){ fprintf(stderr,"Default should be 1.\n"); return 4; }

  exec_or_die(db1, "PRAGMA write_queue=0;");
  v1 = get_int_pragma(db1, "PRAGMA write_queue;");
  v2 = get_int_pragma(db2, "PRAGMA write_queue;");
  printf("after0:%d,%d\n", v1, v2);
  if(v1!=0 || v2!=0){ fprintf(stderr,"Setting to 0 failed\n"); return 5; }

  exec_or_die(db2, "PRAGMA write_queue=1;");
  v1 = get_int_pragma(db1, "PRAGMA write_queue;");
  v2 = get_int_pragma(db2, "PRAGMA write_queue;");
  printf("after1:%d,%d\n", v1, v2);
  if(v1!=1 || v2!=1){ fprintf(stderr,"Re-enable failed\n"); return 6; }

  /* Nested trigger scenario ON */
  exec_or_die(db1, "PRAGMA write_queue=1; CREATE TABLE t(id INTEGER PRIMARY KEY, x);"
                   "CREATE TRIGGER t_ai AFTER INSERT ON t BEGIN INSERT INTO t(x) VALUES(new.x+1); END;" );
  exec_or_die(db1, "INSERT INTO t(x) VALUES(10);");
  v1 = get_int_pragma(db1, "SELECT count(*) FROM t;");
  printf("nested_on_rows:%d\n", v1);
  if(v1!=2){ fprintf(stderr,"Nested trigger (on) failed\n"); return 7; }

  /* Nested trigger scenario OFF */
  exec_or_die(db1, "PRAGMA write_queue=0; CREATE TABLE t2(id INTEGER PRIMARY KEY, x);"
                   "CREATE TRIGGER t2_ai AFTER INSERT ON t2 BEGIN INSERT INTO t2(x) VALUES(new.x+1); END;" );
  exec_or_die(db1, "INSERT INTO t2(x) VALUES(5);");
  v1 = get_int_pragma(db1, "SELECT count(*) FROM t2;");
  printf("nested_off_rows:%d\n", v1);
  if(v1!=2){ fprintf(stderr,"Nested trigger (off) failed\n"); return 8; }

  sqlite3_close(db1); sqlite3_close(db2);
  printf("OK\n");
  return 0;
}
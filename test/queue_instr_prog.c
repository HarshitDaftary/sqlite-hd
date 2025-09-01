#include "sqlite3.h"
#include <stdio.h>
#include <stdlib.h>

static void die(int rc, sqlite3 *db, const char *msg){
  fprintf(stderr, "%s rc=%d err=%s\n", msg, rc, db?sqlite3_errmsg(db):"?" );
  exit(1);
}

int main(void){
  const char *fname = "queue_instr_prog.db";
  remove(fname);
  sqlite3 *db=0; char *errmsg=0; int rc;
  rc = sqlite3_open(fname,&db); if(rc) die(rc,db,"open");
  /* Force small page size so two large rows cannot share a page, ensuring two pager writes */
  rc = sqlite3_exec(db,"PRAGMA page_size=1024;",0,0,&errmsg); if(rc) die(rc,db,"set page_size");
  rc = sqlite3_exec(db,"VACUUM;",0,0,&errmsg); if(rc) die(rc,db,"vacuum");
  rc = sqlite3_exec(db,"CREATE TABLE t(v BLOB);",0,0,&errmsg); if(rc) die(rc,db,"create table");
  rc = sqlite3_exec(db,"BEGIN IMMEDIATE;",0,0,&errmsg); if(rc) die(rc,db,"begin");
  /* First large blob (~900 bytes) */
  rc = sqlite3_exec(db,"INSERT INTO t(v) VALUES(randomblob(900));",0,0,&errmsg); if(rc) die(rc,db,"first insert");
  /* Second large blob should need a new page -> second pager write counted by instrumentation */
  rc = sqlite3_exec(db,"INSERT INTO t(v) VALUES(randomblob(900));",0,0,&errmsg);
  int queueEnabled = getenv("SQLITE_QUEUE_ENABLED") && (getenv("SQLITE_QUEUE_ENABLED")[0]=='1');
  if(getenv("SQLITE_QUEUE_TEST_MODE") && getenv("SQLITE_QUEUE_TEST_MODE")[0]=='1'){
    if(queueEnabled){
      if(rc!=SQLITE_OK){ die(rc,db,"expected OK second insert"); }
    }else{
      if(rc!=SQLITE_BUSY){ fprintf(stderr,"Expected SQLITE_BUSY (5) got %d\n",rc); return 1; }
    }
  }
  if(rc==SQLITE_OK) sqlite3_exec(db,"COMMIT;",0,0,0); else sqlite3_exec(db,"ROLLBACK;",0,0,0);
  sqlite3_close(db);
  printf("DONE rc2=%d queueEnabled=%d\n",rc,queueEnabled);
  return 0;
}

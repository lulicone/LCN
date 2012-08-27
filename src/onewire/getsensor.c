/*****************************************************
** OneWire Temperature Reader
** SQLite
** Serialport
** Posting data to WEB
*****************************************************/

/****************************************************
** Luleå 2012 LCN
****************************************************/

#include <stdio.h>
#include <unistd.h>
#include <getopt.h>
#include "ftdi.h"
#include <memory.h>
#include <string.h>
#include <time.h>
#define DATABASE "/mnt/netgear/sensorData.db"

void logger(char * hdr, char * msg, int lmsg);


 #include <sqlite3.h>
char datetime[20];
char sql[512];
  
  static int callback(void *NotUsed, int argc, char **argv, char **azColName){
    int i;
    for(i=0; i<argc; i++){
      //printf("%s = %s\n", azColName[i], argv[i] ? argv[i] : "NULL");
      strcpy(datetime,argv[0]);
    }
    printf("\n");
    return 0;
  }
  
  int storeSensor(char * addr, float temp){
    sqlite3 *db;
    char *zErrMsg = 0;
    int rc;
    time_t t;
    FILE * fp;

    time(&t);
  
    rc = sqlite3_open(DATABASE, &db);
    if( rc ){
      fprintf(stderr, "Can't open database: %s\n", sqlite3_errmsg(db));
      sqlite3_close(db);
      exit(1);
    }
    sprintf(sql,"SELECT datetime(%d, 'unixepoch', 'localtime')",t); 
    rc = sqlite3_exec(db,sql , callback, 0, &zErrMsg);
    if( rc!=SQLITE_OK ){
      fprintf(stderr, "SQL error: %s\n", zErrMsg);
      sqlite3_free(zErrMsg);
    }


    sprintf(sql,"/opt/bin/wget -O tmp.txt \"harbroad.dyndns.info:8082/cgi-bin/portal.cgi?equip=HOME;date=%s;sensor=%s;data=%0.2f\"",datetime,addr,temp);
    printf("%s\n",sql);
    fp = popen(sql,"r");
    if(fp != NULL)
    {
      fread(sql,1,1,fp);
      pclose(fp);
    }


    sprintf(sql,"INSERT INTO sample (dt,addr,temp) values ('%s','%s',%0.2f)",datetime,addr,temp);

    rc = sqlite3_exec(db, sql, callback, 0, &zErrMsg);
    if( rc!=SQLITE_OK ){
      fprintf(stderr, "SQL error: %s\n", zErrMsg);
      sqlite3_free(zErrMsg);
    }

    sqlite3_close(db);
    return 0;
  }



int hex2Val(char c)
{
	switch(c)
	{
		case '0':case '1':case '2':case '3':case '4':case '5':case '6':case '7':case '8':case '9':
			return c-'0';
			break;
		case 'A':case 'B':case 'C':case 'D':case 'E': case 'F':
			return c-'A'+10;
			break;
                case 'a':case 'b':case 'c':case 'd':case 'e': case 'f':
                        return c-'a'+10;
			break;
		default: 
			return 0;
			break;
	}
	return 0;

}

float convTemp(char * buf)
{
	float ret = 0.0;
	float maxTemp = 125.0;
	float minTemp = -55.0;
	int maxHex = 0x07D0;
	int minHex = 0xFC90;
	int curr = (hex2Val(buf[4])*16 + hex2Val(buf[5]))*256 + (hex2Val(buf[2])*16 + hex2Val(buf[3]));

	//printf("Converted %02X %02X %02X %02X to %04X\n",buf[4],buf[5],buf[2],buf[3],curr);

	if(curr >= 0)
	{
		ret = ((float)((float)curr/(float)maxHex) * maxTemp);
	}
	else
	{
		ret = ((float)((float)curr/(float)minHex) * minTemp);
	}

	return ret;
}


void write1wire(struct ftdi_context * ftdic, char * pbuff,int lbuff)
{

	int f = ftdi_write_data(ftdic,pbuff,lbuff);
        logger("TX:",pbuff,lbuff);
}

int read1wire(struct ftdi_context * ftdic, char * pbuff, int lbuff)
{
	int f = 0;
	usleep(50000);
        f = ftdi_read_data(ftdic, pbuff, lbuff);
	pbuff[f] = 0;
        logger("RX:",pbuff,f);
	return f;
}

void logger(char * hdr, char * msg, int lmsg)
{

	//int cnt = 0;
	//char ascii[1024];
	return;
	//memset(ascii,0,80);
        //printf("%s",hdr);
	//for(cnt=0;cnt<lmsg;cnt++){
        //        printf("0x%02X ",msg[cnt]);
        //        ascii[cnt] = msg[cnt];
        //}
        //printf("%s\n",ascii);
}

void getT(struct ftdi_context *ftdic, int toDB)
{
	char buf[512];
        int f = 0;
	static char addr[80];

	strcpy(addr,"Address");

	write1wire(ftdic,"F28",3);
	f=read1wire(ftdic,buf,512);
	memset(addr,0,80);
	memcpy(addr,buf,16);


	write1wire(ftdic,"W0144\r",6);
	usleep(350000);
        read1wire(ftdic,buf,512);


	write1wire(ftdic,"M",1);
	read1wire(ftdic,buf,512);

        write1wire(ftdic,"W0ABEFFFFFFFFFFFFFFFFFF\r",strlen("W0ABEFFFFFFFFFFFFFFFFFF\r"));
        read1wire(ftdic,buf,512);
	printf("Temp is[%s]:%0.2f C\n",addr,convTemp(buf));	

	if(toDB==1)
	{
		storeSensor(addr,convTemp(buf));	
	}

	f = 1;
	while(f == 1)
	{
		write1wire(ftdic,"f",1);
		read1wire(ftdic,buf,512);

		if(buf[0] == 13)
		{
			f = 0;
		}
		else
		{
			memset(addr,0,80);
			memcpy(addr,buf,16);

       			write1wire(ftdic,"W0144\r",6);
        		usleep(350000);
        		read1wire(ftdic,buf,512);

	       		write1wire(ftdic,"M",1);
        		read1wire(ftdic,buf,512);

        		write1wire(ftdic,"W0ABEFFFFFFFFFFFFFFFFFF\r",strlen("W0ABEFFFFFFFFFFFFFFFFFF\r"));
        		read1wire(ftdic,buf,512);
		        printf("Temp is [%s]:%0.2f C\n",addr,convTemp(buf));

       			if(toDB==1)
        		{
                		storeSensor(addr,convTemp(buf));
        		}


		}
	}
}

int main(int argc, char **argv)
{
    struct ftdi_context ftdic;
    char buf[1024];
    int f, i;
    int vid = 0x0403;
    int pid = 0x6001;
    int baudrate = 9600;
    int interface = INTERFACE_ANY;
    int flag = 1;
    int cnt  = 0;

    while ((i = getopt(argc, argv, "i:v:p:b:")) != -1)
    {
        switch (i)
        {
	case 'i': // 0=ANY, 1=A, 2=B, 3=C, 4=D
		interface = strtoul(optarg, NULL, 0);
		break;
	case 'v':
		vid = strtoul(optarg, NULL, 0);
		break;
	case 'p':
		pid = strtoul(optarg, NULL, 0);
		break;
	case 'b':
		baudrate = strtoul(optarg, NULL, 0);
		break;
	default:
		fprintf(stderr, "usage: %s [-i interface] [-v vid] [-p pid] [-b baudrate]\n", *argv);
		exit(-1);
        }
    }
    if (ftdi_init(&ftdic) < 0)
    {
        fprintf(stderr, "ftdi_init failed\n");
        return EXIT_FAILURE;
    }
    ftdi_set_interface(&ftdic, interface);
    f = ftdi_usb_open(&ftdic, vid, pid);
    if (f < 0)
    {
        fprintf(stderr, "unable to open ftdi device: %d (%s)\n", f, ftdi_get_error_string(&ftdic));
        exit(-1);
    }
    f = ftdi_set_baudrate(&ftdic, 9600);
    if (f < 0)
    {
        fprintf(stderr, "unable to set baudrate: %d (%s)\n", f, ftdi_get_error_string(&ftdic));
        exit(-1);
    }
    
    getT(&ftdic,0);
    getT(&ftdic,1);

    ftdi_usb_close(&ftdic);
    ftdi_deinit(&ftdic);
}

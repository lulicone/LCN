#! /usr/bin/perl

use strict;

####################################################################
#
# OneWire Sensors on 7HAS one wire line
#
####################################################################
use Device::SerialPort;

my $port;  #Global port to use
my @sensors = ();

sub o1w{
	$port = new Device::SerialPort("/dev/ttyAMA0"); 
	$port->user_msg("ON"); 
	$port->baudrate(9600); 
	$port->parity("none"); 
	$port->databits(8); 
	$port->stopbits(1); 
	$port->handshake("none"); 
	$port->write_settings;
	$port->lookclear;
}

sub w1w{
	my ($msg) = @_; 
	$port->write($msg);
}

sub r1w{
	select(undef, undef, undef, 0.3); #sleep 0.3 seconds
	my $res = $port->read(255);
        $res =~ s/[\000-\037]//g;
	return $res;
}

sub hex2val{
	my ($c) = @_;

	$c = lc($c);
        if($c eq "0"){
          return 0;
	}
        if($c eq "1"){
          return 1;
        }
        if($c eq "2"){
          return 2;
        }
        if($c eq "3"){
          return 3;
        }
        if($c eq "4"){
          return 4;
        }
        if($c eq "5"){
          return 5;
        }
        if($c eq "6"){
          return 6;
        }
        if($c eq "7"){
          return 7;
        }
        if($c eq "8"){
          return 8;
        }
        if($c eq "9"){
          return 9;
        }
        if($c eq "a"){
          return 10;
        }
        if($c eq "b"){
          return 11;
        }
        if($c eq "c"){
          return 12;
        }
        if($c eq "d"){
          return 13;
        }
        if($c eq "e"){
          return 14;
        }
        if($c eq "f"){
          return 15;
        }

}



sub convertTemp{
	my ($buff) = @_;
	my $temp = substr($buff,2,4);
        print "$temp\n";
	my $b0 = hex2val(substr($temp,0,1));
        my $b1 = hex2val(substr($temp,1,1));
        my $b2 = hex2val(substr($temp,2,1));
        my $b3 = hex2val(substr($temp,3,1));

	my $t1 = $b0*16 + $b1 + ($b2*16 + $b3)*256;
        return ($t1/2000)*125;

}


sub getFamily{
	my ($fam) = @_;
	@sensors  = ();
        my $rpl   = "";
	w1w("F28");
        $rpl = r1w();
	while($rpl ne ""){
		#print "RX: $rpl \n";
		push(@sensors,$rpl);
		w1w("W0144\r");
		my $tmp = r1w();
		w1w("M");
		$tmp = r1w();
		w1w("W0ABEFFFFFFFFFFFFFFFFFF\r");
		$tmp = r1w();
		print "[$rpl]=$tmp (" . convertTemp($tmp) . ")\n";
		
		w1w("f");
		$rpl = r1w();
	}
}

o1w();
getFamily();
foreach my $sensor (@sensors){
	print "Got: $sensor\n";
}
$port->close();
        
     

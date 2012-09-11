Att använda UART på GPIO pinnar 8 o 10 (ttyAMA0):

* Ta bort consol output till ttyAMA0 från /boot/command.txt
* Kommentera bort getty från /etc/inittab som använder ttyAMA0

Jag lyckades inte med C-Kod få orning på UART:en så jag gick över till Perl:

* På mitt raspberry finns gcc-4.6 men gcc-4.7 krävs, fuskade dir en ln -s /usr/bin/gcc /usr/bin/gcc-4.7
* Kör cpan och install Device::SerialPort OBS! sudo måste köras
    * sudo cpan
    * install Device::SerialPort

Nu ska onewire.pl gå att köra.


Min onewire konfiguration består av:

* Prylarna finns på www.m.nu
  * HA7S, interfacar onewire komponenter 149:-
  * DS18S20, temp givare                  29:- /st




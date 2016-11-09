# Deploy strongSwan IKEv2 VPN on your Linux

This script helps you deploy an IKEv2 VPN server on your Linux machine/VPS with [strongSwan](http://strongswan.org/).

## Disclaimer

I wrote this for myself. I won't coach you, and I don't answer stupid questions.  
Please read through the whole script and try to understand it. It's short. And it's self-documented.

## How to Use

Just modify the beginning of it to meet your need and run it as root.

## Supported Distros
CentOS, Debian, Ubuntu

## Supported Client OSes
Android 4+, iOS 9+, Windows 7+

\*On Android you have to use [strongSwan VPN client](https://play.google.com/store/apps/details?id=org.strongswan.android)
since the stock client doesn't support IKEv2 to this day. It's a neat app. Don't be afraid to use something that is not stock.

## Bug Report/Contribute

I probably don't have time to debug your cousin's friend's aunt's neighbour's dog's problem. Please do your own research first.
If you still believe something is not working, open an issue with what you did, what you see, what the log (/var/log/syslog) says.
Or single-handedly solve it with your genius-level intellect and submit a pull-request. I'm open-minded to everything.

## License

[CC0](https://creativecommons.org/publicdomain/zero/1.0/)

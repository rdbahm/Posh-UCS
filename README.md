# UcsApi

Disclaimers
-----------
Use at your own risk, etc. This project is not affiliated with Polycom.

What it is
----------
A PowerShell module attempting to bring together all the ways to manage and administer Polycom VVX phones and other devices which run Polycom's UCS software. Currently, we support these ways of accessing/controlling UCS:
- REST API (UCS 5.4 and above, REST API must be enabled)
- Web (Web UI must be enabled)
- Polling (Polling must be set to "requestor" mode and a username and password must be set. Additionally, HTTPS is not supported, so requiring secure connections must be turned off.)
- Push (Poor HTTPS support is implemented. Username and Password must be set, and phone must be set to allow push messages.
- Provisioning (Accesses file store where phone stores configuration, logs, etc - only supports FTP at this time)
- SIP (fallback method for when all other methods fail)

We refer to each of the above as an API in the cmdlets despite the technical inaccuracies of doing so.

How To Use
----------
Copy the UCS folder to your modules directory. Open a new PowerShell window. A few things to try:
- Set the credentials for your phones by using one of the Set-Ucs[Name]APICredential cmdlets with one or more sets of credentials. Otherwise, it'll use Polycom factory defaults for REST and Web, UCSToolkit for Push and Poll, and PlcmSpIp for FTP.
- Try Get-UcsPhoneInfo -IPv4Address 192.168.1.50 to get basic phone info and get the idea of the cmdlets.

Support Table
-------------
|Version|Profile|REST|Web|Polling|Push|Provisioning|SIP|
|-------|-------|----|---|-------|----|------------|---|
|[4.1.4.7430](https://github.com/rdbahm/Powershell-UcsApi/wiki/4.1.4.7430)|Lync|Not Possible|Partial|Partial|Supported||Partial|
|5.6.??|Lync|Supported|Supported|Supported|Supported|Supported|Supported|
|[5.7.0.11768](https://github.com/rdbahm/Powershell-UcsApi/wiki/5.7.0.11768)|Lync|Partial|||||
||||||||

Limitations
-----------
To a large extent, I am limited by the documentation I am easily able to find online about each of the "APIs" I'm writing against. Additionally, my experience is primarily with VVX phones running with the Lync base profile, which means I have not implemented some functionality which could be beneficial for Open SIP users. 

The HTTPS programming is really poor and could use a lot of help. It's only implemented on a handful of the base-level functions. As a result, deployments which require HTTPS may not be able to use all functionality.

My testing is primarily with UCS 5.4.5 and above. Documentation on specific supported features is summarized in the Support Table above and more specifically in the Wiki.

Licensing
---------
You can use this and edit the code for your own purposes, but I don't accept any responsibility for problems caused by it directly or indirectly. If you can help improve the code, please make a pull request!

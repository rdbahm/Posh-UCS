# UcsApi

What it is
----------
A PowerShell module attempting to bring together all the ways to manage and administer Polycom VVX phones and other devices which run Polycom's UCS software. Currently, we support these ways of accessing/controlling UCS:
- REST API (UCS 5.4 and above, REST API must be enabled)
- Web (Web UI must be enabled, not tested on any firmware below 5.4.5)
- Polling (Polling must be set to "requestor" mode and a username and password must be set. Additionally, HTTPS is not supported, so requiring secure connections must be turned off.)
- Push (Poor HTTPS support is implemented. Username and Password must be set, and phone must be set to allow push messages.
- Provisioning (Accesses file store where phone stores configuration, logs, etc - only supports FTP at this time)
- SIP (fallback method for when all other methods fail)

We refer to each of the above as an API in the cmdlets despite the technical inaccuracies of doing so.

Limitations
-----------
To a large extent, I am limited by the documentation I am easily able to find online about each of the "APIs" I'm writing against. Additionally, my experience is primarily with VVX phones running with the Lync base profile, which means I have not implemented some functionality which could be beneficial for Open SIP users. 

Licensing
---------
You can use this and edit the code for your own purposes, but I don't accept any responsibility for problems caused by it directly or indirectly. If you can help improve the code, please make a pull request!

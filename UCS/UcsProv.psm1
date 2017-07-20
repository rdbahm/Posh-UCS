$Script:Credential = (New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList ('PlcmSpIp', (ConvertTo-SecureString -String 'PlcmSpIp' -AsPlainText -Force)))

Function Set-UcsProvFTPAPICredential
{
  Param([Parameter(Mandatory)][PsCredential[]]$Credential)
  
  $Script:Credential = $Credential
}

Function Get-UcsProvFTPAPICredential
{
  Param([String]$Username = $null)
  
  if($Username -ne $null)
  {
    Return ($Script:Credential | Where-Object UserName -eq $Username)
  }
  else
  {
    Return $Script:Credential
  }
}

Function Get-UcsProvFTPLog
{
  Param([Parameter(Mandatory)][ValidatePattern('^[a-f0-9]{12}$')][String[]]$MacAddress,
    [Parameter(Mandatory)][String]$FTPServer,
    [Parameter(Mandatory)][ValidateSet('app','boot')][String]$LogType,
  [Parameter(Mandatory)][Management.Automation.PSCredential]$Credential)

  BEGIN
  {
    $CallFiles = New-Object -TypeName System.Collections.ArrayList
    $ProvisioningServer = $FTPServer
    $ProvisioningCredential = $Credential
    
    #Get the master config file so we can know the path we need to take for the call list
    Try 
    {
      $MasterConfigFilename = Get-UcsProvFTPFile -Address $ProvisioningServer -Credential $ProvisioningCredential -Filename '000000000000.cfg'
      $MasterConfig = Get-UcsProvMasterConfig -Filename $MasterConfigFilename
    }
    Catch 
    {
      Write-Error -Message ('Couldn''t get master config file for {0}.' -f $ProvisioningServer) -ErrorAction Stop
    }
  }
  PROCESS
  {
    Foreach($ThisMacAddress in $MacAddress) 
    {
      #Download the call list.
      Try 
      {
        $LogsDirectory = ('{0}{1}' -f $ProvisioningServer, $MasterConfig.LOG_FILE_DIRECTORY)
        $LogfileName = ('{0}-{1}.log' -f $ThisMacAddress,$LogType)
        $Logfile = Get-UcsProvFTPFile -Address $LogsDirectory -Credential $ProvisioningCredential -Filename $LogfileName
      }
      Catch 
      {
        Write-Error -Message ('Couldn''t get log file for {0}, download path was {1}. Filename was {2}.' -f $MacAddress, $LogsDirectory, $LogfileName)
        Continue
      }

      $null = $CallFiles.Add($Logfile)
    }
  } END {
    $AllLogs = New-Object -TypeName System.Collections.ArrayList
    Foreach ($File in $CallFiles) 
    {
      #Run the log list through the parser.
      $Filecontent = Get-Content $File
      $Filecontent = ($Filecontent.Split("`n") | Where-Object { $_.Length -ge 1 } )
      $TheseLogs = New-UcsLog -LogString $Filecontent -LogType $LogType -MacAddress $ThisMacAddress
      $TheseLogs | ForEach-Object -Process {
        $null = $AllLogs.Add($_)
      }
    }

    Return $AllLogs
  }
}

Function Get-UcsProvFTPCallLog
{
  <#
      .SYNOPSIS
      Retrieves a phone's call list.

      .DESCRIPTION
      It attempts to connect to the provisioning server using the username provided by the phone. Once connected, it reads the 000000000000.cfg file to find the directory where call logs are stored. It then looks for the MACADDRESS-calls.xml file corresponding to the requested phone, then parses and returns the result.

      .PARAMETER IPv4Address
      Describe parameter -IPv4Address.

      .EXAMPLE
      Get-Calls -IPv4Address Value
      Describe what this call does

      .NOTES
      Place additional notes here.

      .LINK
      URLs to related sites
      The first link is opened by Get-Help -Online Get-Calls

      .INPUTS
      List of input types that are accepted by this function.

      .OUTPUTS
      List of output types produced by this function.
  #>

  Param([Parameter(Mandatory)][ValidatePattern('^[a-f0-9]{12}$')][String[]]$MacAddress,
    [Parameter(Mandatory)][String]$FTPServer,
  [Parameter(Mandatory)][Management.Automation.PSCredential]$Credential)

  BEGIN {
    $CallFiles = New-Object -TypeName System.Collections.ArrayList
    $ProvisioningServer = $FTPServer
    $ProvisioningCredential = $Credential
    
    #Get the master config file so we can know the path we need to take for the call list
    Try 
    {
      $MasterConfigFilename = Get-UcsProvFTPFile -Address $ProvisioningServer -Credential $ProvisioningCredential -Filename '000000000000.cfg'
      $MasterConfig = Get-UcsProvMasterConfig -Filename $MasterConfigFilename
    }
    Catch 
    {
      Write-Error -Message ('Couldn''t get master config file for {0}.' -f $ProvisioningServer) -ErrorAction Stop
    }
  } PROCESS {
    Foreach($ThisMacAddress in $MacAddress) 
    {
      #Download the call list.
      Try 
      {
        $CallsDirectory = ('{0}{1}' -f $ProvisioningServer, $MasterConfig.CALL_LISTS_DIRECTORY)
        $CallFileName = ('{0}-calls.xml' -f $ThisMacAddress)
        $CallFile = Get-UcsProvFTPFile -Address $CallsDirectory -Credential $ProvisioningCredential -Filename $CallFileName
      }
      Catch 
      {
        Write-Error -Message ('Couldn''t get call file for {0}, download path was {1}. Filename was {2}.' -f $MacAddress, $CallsDirectory, $CallFileName)
        Continue
      }

      $null = $CallFiles.Add($CallFile)
    }
  } END {
    $AllCalls = New-Object -TypeName System.Collections.ArrayList
    Foreach ($File in $CallFiles) 
    {
      #Run the call list through the parser.
      $TheseCalls = Import-UcsProvCallLogXml -Filename $File
      $TheseCalls | ForEach-Object -Process {
        $null = $AllCalls.Add($_)
      }
    }

    $AllCalls = $AllCalls | Sort-Object -Property StartTime
    Return $AllCalls
  }
}

Function Get-UcsProvCallLog 
{
  <#
      .SYNOPSIS
      Retrieves a phone's call list.

      .DESCRIPTION
      This cmdlet is many layers deep. It starts by retrieving the phone's MAC address and its provisioning server. Once it has this information, it attempts to connect to the provisioning server using the username provided by the phone. Once connected, it reads the 000000000000.cfg file to find the directory where call logs are stored. It then looks for the MACADDRESS-calls.xml file corresponding to the requested phone, then parses and returns the result.

      .PARAMETER IPv4Address
      Describe parameter -IPv4Address.

      .EXAMPLE
      Get-Calls -IPv4Address Value
      Describe what this call does

      .NOTES
      Place additional notes here.

      .LINK
      URLs to related sites
      The first link is opened by Get-Help -Online Get-Calls

      .INPUTS
      List of input types that are accepted by this function.

      .OUTPUTS
      List of output types produced by this function.
  #>

  Param(
    [Parameter(Mandatory,HelpMessage = '127.0.0.1',ValueFromPipelineByPropertyName,ValueFromPipeline)][ValidatePattern('^([0-2]?[0-9]{1,2}\.){3}([0-2]?[0-9]{1,2})$')][String[]]$IPv4Address
  )

  BEGIN {
    $CallFiles = New-Object -TypeName System.Collections.ArrayList
  } PROCESS {
    Foreach($ThisIPv4Address in $IPv4Address) 
    {
      #Get the MAC Address and provisioning server.
      #TODO: we're always assuming that the credentials are username/username. Probably we should give an option for user input and skip the phone if the provided credential doesn't match what the phone has.
      $ProvisioningInfo = Get-UcsProvisioningInfo -IPv4Address $ThisIPv4Address
      $MacAddress = (Get-UcsPhoneInfo -IPv4Address $ThisIPv4Address).MacAddress
      $ProvisioningServer = $ProvisioningInfo.ProvServerAddress
      $ProvisioningUser = $ProvisioningInfo.ProvServerUser
      $ProvisioningCredential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList ($ProvisioningUser, (ConvertTo-SecureString -String $ProvisioningUser -AsPlainText -Force))

      #Get the master config file so we can know the path we need to take for the call list
      Try 
      {
        $MasterConfigFilename = Get-UcsProvFTPFile -Address $ProvisioningServer -Credential $ProvisioningCredential -Filename '000000000000.cfg'
        $MasterConfig = Get-UcsProvMasterConfig -Filename $MasterConfigFilename
      }
      Catch 
      {
        Write-Warning -Message ('Couldn''t get master config file for {0}.' -f $ThisIPv4Address)
        Continue
      }
    
      #Download the call list.
      Try 
      {
        $CallsDirectory = ('{0}{1}' -f $ProvisioningServer, $MasterConfig.CALL_LISTS_DIRECTORY)
        $CallFileName = ('{0}-calls.xml' -f $MacAddress)
        $CallFile = Get-UcsProvFTPFile -Address $CallsDirectory -Credential $ProvisioningCredential -Filename $CallFileName
      }
      Catch 
      {
        Write-Warning -Message ('Couldn''t get call file for {0}, download path was {1}. Filename was {2}.' -f $ThisIPv4Address, $CallsDirectory, $CallFileName)
        Continue
      }

      $null = $CallFiles.Add($CallFile)
    }
  } END {
    $AllCalls = New-Object -TypeName System.Collections.ArrayList
    Foreach ($File in $CallFiles) 
    {
      #Run the call list through the parser.
      $TheseCalls = Import-UcsProvCallLogXml -Filename $File
      $TheseCalls | ForEach-Object -Process {
        $null = $AllCalls.Add($_)
      }
    }

    $AllCalls = $AllCalls | Sort-Object -Property StartTime
    Return $AllCalls
  }
}
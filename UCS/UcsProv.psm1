Function Get-UcsProvLog
{
  Param([Parameter(Mandatory)][ValidatePattern('^[a-f0-9]{12}$')][String[]]$MacAddress,
    [Parameter(Mandatory)][ValidateSet('app','boot')][String]$LogType)

  BEGIN
  {
    $CallFiles = New-Object -TypeName System.Collections.ArrayList
  }
  PROCESS
  {
    #Get the master config file so we can know the path we need to take for the call list
    Try 
    {
      $MasterConfigContent = Import-UcsProvFile -FilePath '000000000000.cfg'
      $MasterConfig = Convert-UcsProvMasterConfig -Content $MasterConfigContent
    }
    Catch 
    {
      Write-Error -Message ('Couldn''t get master config file for {0}.' -f $MacAddress) -ErrorAction Stop
    }
    Foreach($ThisMacAddress in $MacAddress) 
    {
      #Download the call list.
      Try 
      {
        $LogPath = $MasterConfig.LOG_FILE_DIRECTORY
        $LogfileName = ('{0}-{1}.log' -f $ThisMacAddress,$LogType)
        if($LogPath.length -gt 0)
        {
          $LogfileName = Join-Path -Path $LogPath -ChildPath $LogfileName
        }
        $Logfile = Import-UcsProvFile -FilePath $LogfileName
      }
      Catch 
      {
        Write-Error -Message ('Couldn''t get log file for {0}, download path was {1}. Filename was {2}.' -f $MacAddress, $LogPath, $LogfileName)
        Continue
      }

      $null = $CallFiles.Add($Logfile)
    }
    
  } END {
    $AllLogs = New-Object -TypeName System.Collections.ArrayList
    Foreach ($File in $CallFiles) 
    {
      #Run the log list through the parser.
      $Filecontent = $File
      $Filecontent = ($Filecontent.Split("`n") | Where-Object { $_.Length -ge 1 } )
      $TheseLogs = New-UcsLog -LogString $Filecontent -LogType $LogType -MacAddress $ThisMacAddress
      $TheseLogs | ForEach-Object -Process {
        $null = $AllLogs.Add($_)
      }
    }

    Return $AllLogs
  }
}

Function Get-UcsProvCallLog
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

  Param([Parameter(Mandatory)][ValidatePattern('^[a-f0-9]{12}$')][String[]]$MacAddress)

  BEGIN
  {
    $CallFiles = New-Object -TypeName System.Collections.ArrayList
  }
  PROCESS
  {
    #Get the master config file so we can know the path we need to take for the call list
    Try 
    {
      $MasterConfigContent = Import-UcsProvFile -FilePath '000000000000.cfg' -ErrorAction Stop
      $MasterConfig = Convert-UcsProvMasterConfig -Content $MasterConfigContent -ErrorAction Stop
    }
    Catch 
    {
      Write-Error -Message ('Couldn''t get master config file for {0}.' -f $MacAddress) -ErrorAction Stop
    }
    Foreach($ThisMacAddress in $MacAddress) 
    {
      #Download the call list.
      Try 
      {
        $CallsDirectory = $MasterConfig.CALL_LISTS_DIRECTORY
        $CallFileName = ('{0}-calls.xml' -f $ThisMacAddress)
        
        if($CallsDirectory.length -gt 0)
        {
          $CallFileName = Join-Path -Path $CallsDirectory -ChildPath $CallFileName
        }
        
        $Logfile = Import-UcsProvFile -FilePath $CallFileName -ReturnPath
      }
      Catch 
      {
        Write-Error -Message ('Couldn''t get log file for {0}, download path was {1}. Filename was {2}.' -f $MacAddress, $CallsDirectory, $CallFileName)
        Continue
      }

      $null = $CallFiles.Add($Logfile)
    }
    
  } END {
    $AllCalls = New-Object -TypeName System.Collections.ArrayList
    Foreach ($File in $CallFiles) 
    {
      #Run the call list through the parser.
      $TheseCalls = Import-UcsProvCallLogXml -Path $File
      $TheseCalls | ForEach-Object -Process {
        $null = $AllCalls.Add($_)
      }
    }

    $AllCalls = $AllCalls | Sort-Object -Property StartTime
    Return $AllCalls
  }
}
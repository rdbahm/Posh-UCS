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
    Foreach($ThisMacAddress in $MacAddress) 
    {
      #Download the call list.
      Try 
      {
        $LogfileName = ('{0}-{1}.log' -f $ThisMacAddress, $LogType)
        $Logfile = Import-UcsProvFile -FilePath $LogfileName -Type Log
      }
      Catch 
      {
        Write-Error -Message ('Couldn''t get log file for {0}, filename was {1}.' -f $MacAddress, $LogfileName)
        Continue
      }

      $null = $CallFiles.Add($Logfile)
    }
    
  } END {
    $AllLogs = New-Object -TypeName System.Collections.ArrayList
    Foreach ($File in $CallFiles) 
    {
      #Run the log list through the parser.
      $Filecontent = $File.Content
      $Filecontent = ($Filecontent.Split("`n") | Where-Object -FilterScript {
          $_.Length -ge 1 
      } )
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
  #>

  Param([Parameter(Mandatory)][ValidatePattern('^[a-f0-9]{12}$')][String[]]$MacAddress)

  BEGIN
  {
    $CallFiles = New-Object -TypeName System.Collections.ArrayList
  }
  PROCESS
  {
    Foreach($ThisMacAddress in $MacAddress) 
    {
      #Download the call list.
      Try 
      {
        $CallFileName = ('{0}-calls.xml' -f $ThisMacAddress)     
        $Logfile = Import-UcsProvFile -FilePath $CallFileName -Type Call
      }
      Catch 
      {
        Write-Error -Message ('Couldn''t get log file for {0}, filename was {2}.' -f $MacAddress, $null, $CallFileName)
        Continue
      }

      $null = $CallFiles.Add($Logfile)
    }
    
  } END {
    $AllCalls = New-Object -TypeName System.Collections.ArrayList
    Foreach ($File in $CallFiles.FullName) 
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

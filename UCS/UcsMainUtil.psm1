Function Get-UcsCleanJSON 
{
  <#
      .SYNOPSIS
      Takes a string intended for a JSON string, sanitizes it, and returns the result.
  #>

  Param (
    [Parameter(Mandatory,HelpMessage = 'Add help message for user',ValueFromPipeline)][String]$String
  )

  $ThisString = $String
    
  $ThisString = $ThisString.Replace('\','\\') #Escape slashes first since they're used for escape characters.
  $ThisString = $ThisString.Replace("`"","\`"") #Escape any double quotes.

  Return $ThisString
}


Function Test-UcsIsAdministrator 
{
  <#
      .SYNOPSIS
      Returns if the current powershell session has administrator rights.
  #>
  $user = [Security.Principal.WindowsIdentity]::GetCurrent()

  Return (New-Object -TypeName Security.Principal.WindowsPrincipal -ArgumentList $user).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)  
}


Function Test-UcsPolycomRootCertificate 
{
  <#
      .SYNOPSIS
      Tests for the presence of the Polycom Root certificate in the certificates store.
  #>
  $MachineCertificates = Get-ChildItem -Path Cert:\LocalMachine\Root
  $UserCertificates = Get-ChildItem -Path Cert:\CurrentUser\Root
  $AllCertificates = $MachineCertificates + $UserCertificates | Where-Object -Property Subject -Like -Value 'CN=Polycom*'

  if($AllCertificates.count -gt 0) 
  {
    Return $true
  }
  else 
  {
    Return $false
  }
}

Function Add-UcsHost 
{
  <#
      .SYNOPSIS
      Adds an entry to the system's hosts file.
  #>
  Param (
    [Parameter(Mandatory,HelpMessage = 'Add help message for user')][string]$IPv4Address,
    [Parameter(Mandatory,HelpMessage = 'Add help message for user')][string]$Hostname
  )
  $Filename = "$env:windir\System32\drivers\etc\hosts"
  Remove-UcsHost -Hostname $Hostname
  $IPv4Address + "`t`t" + $Hostname | Out-File -Encoding ASCII -Append -FilePath $Filename
}

Function Remove-UcsHost 
{
  <#
      .SYNOPSIS
      Removes an entry from the system's hosts file.
  #>
  Param(
    [Parameter(Mandatory,HelpMessage = 'Add help message for user')][string]$Hostname
  )
  $Filename = "$env:windir\System32\drivers\etc\hosts"
  $c = Get-Content -Path $Filename
  $newLines = @()

  foreach ($line in $c) 
  {
    $bits = [regex]::Split($line, '\t+')
    if ($bits.count -eq 2) 
    {
      if ($bits[1] -ne $Hostname) 
      {
        $newLines += $line
      }
    }
    else 
    {
      $newLines += $line
    }
  }

  # Write file
  Clear-Content -Path $Filename
  foreach ($line in $newLines) 
  {
    $line | Out-File -Encoding ASCII -Append -FilePath $Filename
  }
}


Function Convert-UcsUptimeString 
{
  <#
      .SYNOPSIS
      Takes a UCS API formatted uptime string and returns a timespan. (0 day 0:55:11)

      .DESCRIPTION
      Add a more complete description of what the function does.

      .PARAMETER Uptime
      A timespan in string format, formatted in Polycom Unified Communications Software format - such as "2 days 12:44:11." Allows input of "day" or "days" and additionally for the hours to be reprsented as a single number without a leading 0.

      .OUTPUTS
      A timespan object.
  #>

  Param([Parameter(Mandatory,HelpMessage = 'Add help message for user')][ValidatePattern('^\d+( Day(s)? )|(\.)\d{1,2}:\d{2}:\d{2}$')][String]$Uptime)

  if($Uptime -like "*Day*") {
    $UptimeFirstSpace = $Uptime.IndexOf(' ')
    $UptimeDays = $Uptime.Substring(0,$UptimeFirstSpace)
  } else {
    #Format is more like 3.02:24:46, which is weird but sometimes happens.
    $null = $Uptime -match '^\d+'
    $UptimeDays = $Matches[0]
  }
  
  $UptimeThisIndex = $Uptime.Length - 1 #End of string
  $UptimeSeconds = $Uptime.Substring(($UptimeThisIndex - 1),2)
  $UptimeThisIndex = $UptimeThisIndex - 3
  $UptimeMinutes = $Uptime.Substring(($UptimeThisIndex - 1),2)
  $UptimeThisIndex = $UptimeThisIndex - 3
  $UptimeHours = $Uptime.Substring(($UptimeThisIndex - 1),2).Trim(' ')

  $UptimeTimeSpan = New-TimeSpan -Days $UptimeDays -Hours $UptimeHours -Minutes $UptimeMinutes -Seconds $UptimeSeconds

  Return $UptimeTimeSpan
}


Function Get-UcsStatusCodeString 
{
  <#
      .SYNOPSIS
      Turns a Polycom status code into a stringified description of what it represents. Optionally allows the user to include IPv4 address and Endpoint to allow return of additional information.
      .PARAMETER IPv4Address
      The network address in IPv4 notation, such as 192.123.45.67.
  #>
  Param([Parameter(Mandatory,HelpMessage = 'Add help message for user',ValueFromPipelineByPropertyName,ValueFromPipeline)][int]$StatusCode,
    [ValidatePattern('^([0-2]?[0-9]{1,2}\.){3}([0-2]?[0-9]{1,2})$')][String]$IPv4Address,
  [String]$ApiEndpoint)

  BEGIN {
    $OutputArray = New-Object -TypeName System.Collections.ArrayList
  } PROCESS {
    Foreach ($ThisStatusCode in $StatusCode) 
    {
      $ResponseOK = $false #Set to true if this code indicates the process completed successfully.
      $StatusString = 'Unknown status code.'
      $Exception = $null

      if($ThisStatusCode -eq $null) 
      {
        $ResponseOK = $false
        $StatusString = 'No response returned from API.'
        $Exception = New-Object System.Runtime.InteropServices.ExternalException -ArgumentList $StatusString
      }
      elseif($ThisStatusCode -eq 2000) 
      {
        $ResponseOK = $true
        $StatusString = 'API executed successfully.'
      }
      elseif($ThisStatusCode -eq 4000) 
      {
        $ResponseOK = $false
        $StatusString = 'Invalid input parameters.'
        $Exception = New-Object System.ArgumentException -ArgumentList $StatusString
      }
      elseif($ThisStatusCode -eq 4001) 
      {
        $ResponseOK = $false
        $StatusString = 'Device busy.'
        $Exception = New-Object System.Runtime.InteropServices.ExternalException -ArgumentList $StatusString
      }
      elseif($ThisStatusCode -eq 4002) 
      {
        $ResponseOK = $false
        $StatusString = 'Line not registered.'
        $Exception = New-Object System.InvalidOperationException -ArgumentList $StatusString
      }
      elseif($ThisStatusCode -eq 4003) 
      {
        $ResponseOK = $false
        $StatusString = 'Operation not allowed.'
        $Exception = New-Object System.InvalidOperationException -ArgumentList $StatusString
      }
      elseif($ThisStatusCode -eq 4004) 
      {
        $ResponseOK = $false
        $StatusString = 'Operation not supported.'
        $Exception = New-Object System.InvalidOperationException -ArgumentList $StatusString
      }
      elseif($ThisStatusCode -eq 4005) 
      {
        $ResponseOK = $false
        $StatusString = 'Line does not exist.'
        $Exception = New-Object System.InvalidOperationException -ArgumentList $StatusString
      }
      elseif($ThisStatusCode -eq 4006) 
      {
        $ResponseOK = $false
        $StatusString = 'URLs not configured.'
        $Exception = New-Object System.InvalidOperationException -ArgumentList $StatusString
      }
      elseif($ThisStatusCode -eq 4007) 
      {
        $ResponseOK = $true
        $StatusString = 'Call does not exist.'
        $Exception = New-Object System.NullReferenceException -ArgumentList $StatusString
      }
      elseif($ThisStatusCode -eq 4008) 
      {
        $ResponseOK = $false
        $StatusString = 'Configuration export failed.'
        $Exception = New-Object System.Runtime.InteropServices.ExternalException -ArgumentList $StatusString
      }
      elseif($ThisStatusCode -eq 4009) 
      {
        $ResponseOK = $false
        $StatusString = 'Input size limit exceeded.'
        $Exception = New-Object System.InvalidOperationException -ArgumentList $StatusString
      }
      elseif($ThisStatusCode -eq 4010) 
      {
        $ResponseOK = $false
        $StatusString = 'Default password not permitted.'
        $Exception = New-Object System.InvalidOperationException -ArgumentList $StatusString
      }
      elseif($ThisStatusCode -eq 5000) 
      {
        $ResponseOK = $false
        $StatusString = 'Failed to process request.'
        $Exception = New-Object System.Runtime.InteropServices.ExternalException -ArgumentList $StatusString
      }

      $Result = $ThisStatusCode | Select-Object -Property @{
        Name       = 'StatusCode'
        Expression = {
          $ThisStatusCode
        }
      }, @{
        Name       = 'IsSuccess'
        Expression = {
          $ResponseOK
        }
      }, @{
        Name       = 'StatusString'
        Expression = {
          $StatusString
        }
      }, @{
        Name       = 'Exception'
        Expression = {
          $Exception
        }
      }
      if($ApiEndpoint) 
      {
        $Result = $Result | Select-Object -Property *, @{
          Name       = 'ApiEndpoint'
          Expression = {
            $ApiEndpoint
          }
        }
      }
      if($IPv4Address) 
      {
        $Result = $Result | Select-Object -Property *, @{
          Name       = 'IPv4Address'
          Expression = {
            $IPv4Address
          }
        }
      }
      $null = $OutputArray.Add($Result)
    }
  } END {
    Return $OutputArray
  }
}

Function Test-UcsSkypeModuleIsAvailable 
{
  $Modules = ('Lync', 'SkypeForBusiness')
  $ReturnValue = $false

  Foreach($Module in $Modules) 
  {
    if(Get-Module -ListAvailable | Where-Object -FilterScript {
        $_.Name -eq $Module 
    }) 
    {
      Write-Debug -Message ('{0} is available on this system.' -f $Module)
      $ReturnValue = $true

      if(Get-Module -Name $Module) 
      {
        Write-Debug -Message ('{0} module is loaded and ready to use.' -f $Module)
      }
      else 
      {
        Write-Debug -Message ('{0} module is available but unloaded. Now importing.' -f $Module)
        Import-Module -Name $Module
      }
    }
  }

  Return $ReturnValue
}

Function New-UcsLog
{
  Param([Parameter(Mandatory,ValueFromPipeline)][String[]]$LogString,
    [Parameter(Mandatory)][String][ValidateSet('app','boot')]$LogType,
    [Parameter(ValueFromPipelineByPropertyName)][ValidatePattern('^([0-2]?[0-9]{1,2}\.){3}([0-2]?[0-9]{1,2})$')][String]$IPv4Address = "",
  [Parameter(ValueFromPipelineByPropertyName)][ValidatePattern('^[a-f0-9]{12}$')][String]$MacAddress = "")
  BEGIN
  {
    $LogOutput = New-Object System.Collections.ArrayList
  }
  PROCESS
  {
      $SplitString = $LogString.Split("`n") | Where-Object -FilterScript {$_.Length -gt 2 }
      Foreach ($Line in $SplitString) 
      {
        Try 
        {
          $SplitLine = $Line.Split('|')
          $Message = $SplitLine[4..(($Splitline.Count)-1)] -Join "|" #After the 4th pipe, sometimes the log has additional pipes just to break parsing.
          
          $RawTime = $SplitLine[0]
          if($RawTime -match '\d+\.\d{3}') 
          {
            #This is a time since boot.
            $Datetime = $null
            $TimeSinceBoot = New-TimeSpan -Seconds $RawTime
          }
          else 
          {
            #This is actual time. 
            #MMDDHHMMSS
            $TimeSinceBoot = $null
            Try
            {
              $Datetime = Get-Date -Month $RawTime.Substring(0,2) -Day $RawTime.Substring(2,2) -Hour $RawTime.Substring(4,2)  -Minute $RawTime.Substring(6,2) -Second $RawTime.Substring(8,2) -Millisecond 0 -ErrorAction Stop
            }
            Catch
            {
              Write-Debug "Invalid datetime detected: $RawTime"
              $Datetime = $null
            }
            if($Datetime -gt (Get-Date)) 
            {
              $Datetime = $Datetime.AddYears(-1) #because the string doesn't specify a year, we need to correct it if it's in the future.
            }
            
            if($LogType -eq 'boot') {
              #Boot times are universal time, not local time.
              $Datetime = $Datetime + (($Datetime)-($Datetime).ToUniversalTime())
            }
          }

          $ThisOutput = 1 | Select-Object -Property @{
            Name       = 'RawTime'
            Expression = {
              $SplitLine[0]
            }
          }, @{
            Name       = 'DateTime'
            Expression = {
              $Datetime
            }
          }, @{
            Name       = 'TimeSinceBoot'
            Expression = {
              $TimeSinceBoot
            }
          }, @{
            Name       = 'Id'
            Expression = {
              $SplitLine[1].Trim(' ')
            }
          }, @{
            Name       = 'Level'
            Expression = {
              $SplitLine[2]
            }
          }, @{
            Name       = 'MissedEvents'
            Expression = {
              $SplitLine[3]
            }
          }, @{
            Name       = 'Message'
            Expression = {
              $Message
            }
          }, @{
            Name       = 'LogType'
            Expression = {
              $LogType
            }
          }
          
          if($IPv4Address.length -ge 7) {
            $ThisOutput | Select-Object *, @{
              Name       = 'IPv4Address'
              Expression = {
                $IPv4Address
              }
            }
          } 
          if($MacAddress.length -eq 12) {
            $ThisOutput | Select-Object *, @{
              Name       = 'MacAddress'
              Expression = {
                $MacAddress
              }
            }
          }
          $null = $LogOutput.Add($ThisOutput)
        } Catch 
        {
          Write-Debug -Message "Skipped $Line due to error $_"
        }
        }
  }
  END
  {
    Return $LogOutput
  }

}

Function Convert-UcsVersionNumber
{
  Param([Parameter(Mandatory,ValueFromPipeline)][ValidatePattern('(\d+[A-Z]?\.){3}\d{4,}[A-Z]*(\s.+)?')][String]$FirmwareRelease)
  
  $Success = $FirmwareRelease -match "(?<major>\d+)\.(?<minor>\d+)\.(?<build>\d+[A-Z]?)\.(?<revision>\d+[A-Z]*)(?<notes>\s.+)?"
  
  if($Success)
  {
    $OutputResult = 1 | Select-Object @{Name="FirmwareRelease";Expression={$FirmwareRelease}},@{Name="Major";Expression={$Matches['major']}},@{Name="Minor";Expression={$Matches['minor']}},@{Name="Build";Expression={$Matches['build']}},@{Name="Revision";Expression={$Matches['revision']}},@{Name="Note";Expression={($Matches['notes']).Trim()}}
    Return $OutputResult
  }
  else
  {
    Write-Error "Couldn't parse firmware version $FirmwareRelease" -Category InvalidData
  }
}

Function Get-UcsUnixTime
{
  $UnixTime = [Math]::Round( (((Get-Date) - (Get-Date -Date 'January 1 1970 00:00:00.00')).TotalSeconds), 0)
  Return $UnixTime
}

Function New-UcsCallObject
{
  Param(`
    [String][ValidatePattern('^(0x)?[a-f0-9]{7,8}$')]$CallHandle = $null,
    [ValidateSet('','Incoming','Outgoing','Missed','Placed','Received','In','Out')][String]$Type = $null,
    [ValidateSet('','Conference','Normal','Rejected','RemotelyHandled','Transferred','Busy','UserForwarded','Partial')][String]$Disposition = $null,
    [String[]]$RemotePartyName = $null,
    [String[]]$RemotePartyNumber = $null,
    [String[]]$LocalPartyName = $null,
    [String[]]$LocalPartyNumber = $null,
    [String[]]$ConnectionName = $null,
    [String[]]$ConnectionNumber = $null,
    [ValidateSet('Dialtone','Connected','CallHold','Hold','Setup','RingBack','Offering','Log','Proceeding','')][String]$CallState = $null,
    [ValidateSet('SIP','')][String]$Protocol = $null,
    [Nullable[DateTime]]$StartTime = $null,
    [Nullable[TimeSpan]]$Duration = $null,
    [ValidateRange(0,100)][Int]$LineID = -1,
    [ValidateRange(0,100)][Int]$CallSequence = -1,
    [ValidatePattern('^(\d{1,2}\*?)?$')][String]$UIAppearanceIndex = $null,
    [Nullable[Bool]]$ActiveCall = $null,
    [Nullable[Bool]]$Ringing = $null,
    [Nullable[Bool]]$Muted = $null,
    [ValidateRange(0,65535)][Int]$RTPPort = -1,
    [ValidateRange(0,65535)][Int]$RTCPPort = -1,
    [ValidatePattern('^[a-f0-9]{12}$')][String]$MacAddress = $null,
    [Parameter(HelpMessage = '127.0.0.1',ValueFromPipelineByPropertyName,ValueFromPipeline)][ValidatePattern('^([0-2]?[0-9]{1,2}\.){3}([0-2]?[0-9]{1,2})$')][String]$IPv4Address = $null,
    [Switch]$ExcludeNullProperties,
    [Switch]$IsLog ` #For logs, we don't want to compute based on current time.
  )

  $ThisOutputCall = New-Object -TypeName PSObject
  $ThisOutputCall | Add-Member -MemberType NoteProperty -Name CallHandle -Value $CallHandle
  $ThisOutputCall | Add-Member -MemberType NoteProperty -Name Type -Value $Type
  $ThisOutputCall | Add-Member -MemberType NoteProperty -Name Disposition -Value $Disposition
  $ThisOutputCall | Add-Member -MemberType NoteProperty -Name RemotePartyName -Value $RemotePartyName
  $ThisOutputCall | Add-Member -MemberType NoteProperty -Name RemotePartyNumber -Value $RemotePartyNumber
  $ThisOutputCall | Add-Member -MemberType NoteProperty -Name LocalPartyName -Value $LocalPartyName
  $ThisOutputCall | Add-Member -MemberType NoteProperty -Name LocalPartyNumber -Value $LocalPartyNumber
  $ThisOutputCall | Add-Member -MemberType NoteProperty -Name ConnectionName -Value $ConnectionName
  $ThisOutputCall | Add-Member -MemberType NoteProperty -Name ConnectionNumber -Value $ConnectionNumber
  $ThisOutputCall | Add-Member -MemberType NoteProperty -Name CallState -Value $CallState
  $ThisOutputCall | Add-Member -MemberType NoteProperty -Name Protocol -Value $Protocol
  $ThisOutputCall | Add-Member -MemberType NoteProperty -Name StartTime -Value $StartTime
  $ThisOutputCall | Add-Member -MemberType NoteProperty -Name Duration -Value $Duration
  $ThisOutputCall | Add-Member -MemberType NoteProperty -Name LineID -Value $LineID
  $ThisOutputCall | Add-Member -MemberType NoteProperty -Name CallSequence -Value $CallSequence
  $ThisOutputCall | Add-Member -MemberType NoteProperty -Name UIAppearanceIndex -Value $UIAppearanceIndex
  $ThisOutputCall | Add-Member -MemberType NoteProperty -Name ActiveCall -Value $UIAppearanceIndex #Temporary value
  $ThisOutputCall | Add-Member -MemberType NoteProperty -Name Ringing -Value $Ringing
  $ThisOutputCall | Add-Member -MemberType NoteProperty -Name Muted -Value $Muted
  $ThisOutputCall | Add-Member -MemberType NoteProperty -Name RTPPort -Value $RTPPort
  $ThisOutputCall | Add-Member -MemberType NoteProperty -Name RTCPPort -Value $RTCPPort

  if($MacAddress.Length -eq 12)
  {
    $ThisOutputCall | Add-Member -MemberType NoteProperty -Name MacAddress -Value $MacAddress
  }
  if($IPv4Address.Length -gt 0)
  {
    $ThisOutputCall | Add-Member -MemberType NoteProperty -Name IPv4Address -Value $IPv4Address
  }

  #Null any properties that weren't included.
  $NullProperties = New-Object System.Collections.ArrayList
  Foreach($Property in ($ThisOutputCall | Get-Member -MemberType NoteProperty | Select-Object -ExpandProperty Name))
  {
    $ThisValue = $ThisOutputCall.$Property
    $IsNull = $false

    if($ThisValue -eq $null)
    {
      $IsNull = $true
    }
    elseif($ThisValue.GetType().Name -eq "Int32")
    {
      if($ThisValue -le 0)
      {
        $IsNull = $true
      }
    }
    elseif($ThisValue.GetType().Name -eq "String")
    {
      if($ThisValue -eq "")
      {
        $IsNull = $true
      }
    }
    elseif($ThisValue.GetType().Name -eq "String[]")
    {
      #String array, smash into a string if it's only one long.
      if($ThisValue.Count -eq 0)
      {
        $IsNull = $true
      }
      elseif($ThisValue.Count -eq 1)
      {
        $ThisOutputCall.$Property = $ThisValue[0]
        Write-Debug "Property $Property was a single-value array. Smashed to string."
      }
    }
    else
    {
      Write-Debug "Value for property $Property was non-null: $ThisValue"
    }

    if($IsNull)
    {
      $ThisOutputCall.$Property = $null
      $null = $NullProperties.Add($Property)
    }
  }

  #Compute a start time based on duration and current time.
  if($ThisOutputCall.StartTime -eq $null -and $ThisOutputCall.Duration -ne $null -and $IsLog -ne $true)
  {
    $ThisOutputCall.StartTime = (Get-Date) - $ThisOutputCall.Duration
    $NullProperties = $NullProperties | Where-Object { $_ -ne "StartTime" }
  }
  elseif($ThisOutputCall.Duration -eq $null -and $ThisOutputCall.StartTime -ne $null -and $IsLog -ne $true)
  {
    #Calculate the duration. Drop milliseconds.
    $ThisDuration = (Get-Date) - (Get-Date $ThisOutputCall.StartTime)
    $ThisOutputCall.Duration = New-TimeSpan -Seconds ([Int]$ThisDuration.TotalSeconds)
    $NullProperties = $NullProperties | Where-Object { $_ -ne "Duration" }
  }

  if($ThisOutputCall.CallHandle -ne $null -and $ThisOutputCall.CallHandle -notmatch '^0x?[a-f0-9]{7,8}$' )
  {
    #If there's a callhandle that needs modification.
    $ThisOutputCall.CallHandle = ('0x{0}' -f $ThisOutputCall.CallHandle)
  }

  if($ThisOutputCall.UIAppearanceIndex -ne $null)
  {
    #If a UI Appearance Index is provided, compute if this is the active call.
    if($ThisOutputCall.UIAppearanceIndex -match '^\d+\*$')
    {
      $ActiveCall = $true
    }
    else
    {
      $ActiveCall = $false
    }
    $ThisOutputCall.UIAppearanceIndex = [Int]($ThisOutputCall.UIAppearanceIndex.Trim(' *'))
    $ThisOutputCall.ActiveCall = $ActiveCall
  }

  if($ThisOutputCall.CallState -eq 'CallHold')
  {
    #V1 REST API returns "CallHold" instead of "Hold," so we coerce it into the right format.
    $ThisOutputCall.CallState = 'Hold'
  }
  elseif($ThisOutputCall.CallState -eq 'Proceeding')
  {
    $ThisOutputCall.CallState = 'Connected'
  }

  #We standardize calls and call logs with the same names.
  if($ThisOutputCall.Type -eq 'Placed' -or $ThisOutputCall.Type -eq 'Out')
  {
    $ThisOutputCall.Type = 'Outgoing'
  }
  elseif($ThisOutputCall.Type -eq 'Received' -or $ThisOutputCall.Type -eq 'In')
  {
    $ThisOutputCall.Type = 'Incoming'
  }

  if($ExcludeNullProperties)
  {
    $ThisOutputCall = $ThisOutputCall | Select-Object -Property * -ExcludeProperty $NullProperties
  }

  Return $ThisOutputCall
}

Function Start-UcsSimultaneousJob
{
  <# Work in progress. Input a scriptblock with a placeholder for IP address. Use $Arg[0] as the placeholder for IP address. #>
  [CmdletBinding()]
  Param( [ScriptBlock]$ScriptBlock, [Parameter(Mandatory,HelpMessage = '127.0.0.1',ValueFromPipelineByPropertyName,ValueFromPipeline)][ValidatePattern('^([0-2]?[0-9]{1,2}\.){3}([0-2]?[0-9]{1,2})$')][String[]]$IPv4Address, [Int]$MaxJobs = 40, [Int]$TimeoutSeconds = 120 )
  
  $AllJobs = New-Object System.Collections.ArrayList
  Foreach($ThisIPv4Address in $IPv4Address)
  {
    if($AllJobs.Count -ge $MaxJobs)
    {
      Write-Debug "Hit max job count. Waiting..."
      $WaitedJobs = Wait-Job -Id $AllJobs -Any
      $WaitedJobs = Get-Job -Id $AllJobs | ? State -ne "Running"
      Write-Debug ("Got {0} done jobs." -f $WaitedJobs.Count)
      
      Foreach ($DoneJob in $WaitedJobs)
      {
        Write-Debug ("Got job {0}" -f $DoneJob.Name)
        $DoneJob | Receive-Job #Output the result.
        $null = $AllJobs.Remove($DoneJob.Id)
      }
    }
    
    $ThisJob = Start-Job -ScriptBlock $ScriptBlock -ArgumentList $ThisIPv4Address -Name ("{0}-{1}" -f $ThisIPv4Address,[Guid]::NewGuid().ToString())
    $null = $AllJobs.Add($ThisJob.Id)
  }
  
  Write-Debug ("After completion of loops, {0} jobs are still pending at {1}" -f $AllJobs.Count,(Get-Date).ToShortTimeString())
  $FinalJobs = Wait-Job -Id $AllJobs -Timeout $TimeoutSeconds
  Write-Debug ("After waiting, {0} jobs are finished at {1}." -f $FinalJobs.Count,(Get-Date).ToShortTimeString())
  
  Foreach ($DoneJob in $FinalJobs)
  {
    $DoneJob | Receive-Job #Output the result.
    $null = $AllJobs.Remove($DoneJob.Id) #remove this ID from the remaining jobs.
  }
  
  Foreach($UnfinishedJob in $AllJobs)
  {
    Write-Warning ("Job {0} failed to complete within timeout period." -f $UnfinishedJob.Name)
    $null = $UnfinishedJob | Stop-Job
    $null = $UnfinishedJob | Remove-Job
  }
  
}
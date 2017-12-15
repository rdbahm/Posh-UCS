Function Get-UcsCleanJSON 
{
  <#
      .SYNOPSIS
      Takes a string intended for a JSON string, sanitizes it, and returns the result.

      .DESCRIPTION
      Add a more complete description of what the function does.

      .PARAMETER String
      Describe parameter -String.

      .EXAMPLE
      Get-UcsCleanJSON -String Value
      Describe what this call does

      .NOTES
      Place additional notes here.

      .LINK
      URLs to related sites
      The first link is opened by Get-Help -Online Get-UcsCleanJSON

      .INPUTS
      List of input types that are accepted by this function.

      .OUTPUTS
      List of output types produced by this function.
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
      SYNOPSIS
      Returns if the current powershell session has administrator rights.
  #>
  $user = [Security.Principal.WindowsIdentity]::GetCurrent()

  Return (New-Object -TypeName Security.Principal.WindowsPrincipal -ArgumentList $user).IsInRole([Security.Principal.WindowsBuiltinRole]::Administrator)  
}


Function Test-UcsPolycomRootCertificate 
{
  <#
      .SYNOPSIS
      Describe purpose of "Test-UcsPolycomRootCertificate" in 1-2 sentences.

      .DESCRIPTION
      Add a more complete description of what the function does.

      .EXAMPLE
      Test-UcsPolycomRootCertificate
      Describe what this call does

      .NOTES
      Place additional notes here.

      .LINK
      URLs to related sites
      The first link is opened by Get-Help -Online Test-UcsPolycomRootCertificate

      .INPUTS
      List of input types that are accepted by this function.

      .OUTPUTS
      List of output types produced by this function.
  #>


  <#
      SYNOPSIS
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
      Describe purpose of "Add-UcsHost" in 1-2 sentences.

      .DESCRIPTION
      Add a more complete description of what the function does.

      .PARAMETER IPv4Address
      Describe parameter -IPv4Address.

      .PARAMETER Hostname
      Describe parameter -Hostname.

      .EXAMPLE
      Add-UcsHost -IPv4Address Value -Hostname Value
      Describe what this call does

      .NOTES
      Place additional notes here.

      .LINK
      URLs to related sites
      The first link is opened by Get-Help -Online Add-UcsHost

      .INPUTS
      List of input types that are accepted by this function.

      .OUTPUTS
      List of output types produced by this function.
  #>


  <#
      SYNOPSIS
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
      Describe purpose of "Remove-UcsHost" in 1-2 sentences.

      .DESCRIPTION
      Add a more complete description of what the function does.

      .PARAMETER Hostname
      Describe parameter -Hostname.

      .EXAMPLE
      Remove-UcsHost -Hostname Value
      Describe what this call does

      .NOTES
      Place additional notes here.

      .LINK
      URLs to related sites
      The first link is opened by Get-Help -Online Remove-UcsHost

      .INPUTS
      List of input types that are accepted by this function.

      .OUTPUTS
      List of output types produced by this function.
  #>


  <#
      SYNOPSIS
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

      .EXAMPLE
      Convert-UcsUptimeString -Uptime Value
      Describe what this call does

      .NOTES
      Place additional notes here.

      .LINK
      URLs to related sites
      The first link is opened by Get-Help -Online Convert-UcsUptimeString

      .INPUTS
      List of input types that are accepted by this function.

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
      Describe purpose of "Get-UcsStatusCodeString" in 1-2 sentences.

      .DESCRIPTION
      Add a more complete description of what the function does.

      .PARAMETER StatusCode
      Describe parameter -StatusCode.

      .PARAMETER IPv4Address
      Describe parameter -IPv4Address.

      .PARAMETER ApiEndpoint
      Describe parameter -ApiEndpoint.

      .EXAMPLE
      Get-UcsStatusCodeString -StatusCode Value -IPv4Address Value -ApiEndpoint Value
      Describe what this call does

      .NOTES
      Place additional notes here.

      .LINK
      URLs to related sites
      The first link is opened by Get-Help -Online Get-UcsStatusCodeString

      .INPUTS
      List of input types that are accepted by this function.

      .OUTPUTS
      List of output types produced by this function.
  #>


  <#
      SYNOPSIS
      Turns a Polycom status code into a stringified description of what it represents. Optionally allows the user to include IPv4 address and Endpoint to allow return of additional information.
      PARAMETER IPv4Address
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

      if($ThisStatusCode -eq $null) 
      {
        $ResponseOK = $false
        $StatusString = 'No response returned from API.'
      }
      elseif($ThisStatusCode -eq 2000) 
      {
        $ResponseOK = $true
        $StatusString = 'The operation completed successfully.'
      }
      elseif($ThisStatusCode -eq 4000) 
      {
        $ResponseOK = $false
        $StatusString = 'Invalid input parameters.'
      }
      elseif($ThisStatusCode -eq 4001) 
      {
        $ResponseOK = $false
        $StatusString = 'The device is busy.'
      }
      elseif($ThisStatusCode -eq 4002) 
      {
        $ResponseOK = $false
        $StatusString = 'Line is not registered.'
      }
      elseif($ThisStatusCode -eq 4003) 
      {
        $ResponseOK = $false
        $StatusString = 'Operation not allowed.'
      }
      elseif($ThisStatusCode -eq 4004) 
      {
        $ResponseOK = $false
        $StatusString = 'Operation not supported.'
      }
      elseif($ThisStatusCode -eq 4005) 
      {
        $ResponseOK = $false
        $StatusString = 'Invalid line selection.'
      }
      elseif($ThisStatusCode -eq 4006) 
      {
        $ResponseOK = $false
        $StatusString = 'URLs not configured.'
      }
      elseif($ThisStatusCode -eq 4007) 
      {
        $ResponseOK = $true
        $StatusString = 'Call does not exist.'
      }
      elseif($ThisStatusCode -eq 4008) 
      {
        $ResponseOK = $false
        $StatusString = 'Configuration export failed.'
      }
      elseif($ThisStatusCode -eq 4009) 
      {
        $ResponseOK = $false
        $StatusString = 'Input size limit exceeded.'
      }
      elseif($ThisStatusCode -eq 4010) 
      {
        $ResponseOK = $false
        $StatusString = 'Default password not permitted.'
      }
      elseif($ThisStatusCode -eq 5000) 
      {
        $ResponseOK = $false
        $StatusString = 'Failed to process request due to an internal error.'
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
  <#
      .SYNOPSIS
      Describe purpose of "Test-UcsSkypeModuleIsAvailable" in 1-2 sentences.

      .DESCRIPTION
      Add a more complete description of what the function does.

      .EXAMPLE
      Test-UcsSkypeModuleIsAvailable
      Describe what this call does

      .NOTES
      Place additional notes here.

      .LINK
      URLs to related sites
      The first link is opened by Get-Help -Online Test-UcsSkypeModuleIsAvailable

      .INPUTS
      List of input types that are accepted by this function.

      .OUTPUTS
      List of output types produced by this function.
  #>


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
    [Parameter(HelpMessage = '127.0.0.1',ValueFromPipelineByPropertyName)][ValidatePattern('^([0-2]?[0-9]{1,2}\.){3}([0-2]?[0-9]{1,2})$')][String]$IPv4Address = "",
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
            $Datetime = Get-Date -Month $RawTime.Substring(0,2) -Day $RawTime.Substring(2,2) -Hour $RawTime.Substring(4,2)  -Minute $RawTime.Substring(6,2) -Second $RawTime.Substring(8,2) -Millisecond 0
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
  Param([Parameter(Mandatory,ValueFromPipeline)][ValidatePattern('(\d+\.){3}\d{4,}[A-Z]?')][String]$FirmwareRelease)
  
  $Success = $FirmwareRelease -match "(?<major>\d+)\.(?<minor>\d+)\.(?<bugfix>\d+)\.(?<build>\d+[A-Z]?)"
  
  if($Success)
  {
    $OutputResult = 1 | Select-Object @{Name="FirmwareRelease";Expression={$FirmwareRelease}},@{Name="Major";Expression={$Matches['major']}},@{Name="Minor";Expression={$Matches['minor']}},@{Name="Bugfix";Expression={$Matches['bugfix']}},@{Name="Build";Expression={$Matches['Build']}}
    Return $OutputResult
  }
  else
  {
    Write-Error "Couldn't parse firmware version $FirmwareRelease" -Category InvalidData
  }
}
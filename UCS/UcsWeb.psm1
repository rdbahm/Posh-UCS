$Script:Port = 80
$Script:UseHTTPS = $false
$Script:DefaultTimeout = New-Timespan -Seconds 2
$Script:DefaultRetries = 3 #3 means that it'll try to connect 3 times: Once, then two retries.

$Script:Credential = (New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList ('Polycom', (ConvertTo-SecureString -String '456' -AsPlainText -Force)))


Function Set-UcsWebAPIConnectionSetting
{
  Param([Int][ValidateRange(1,65535)]$Port = $null,
    [Bool]$UseHTTPS = $null,
    [Timespan]$Timeout = $null,
    [Int][ValidateRange(1,100)]$Retries = $null
  )
  
  if($Port -ne $null)
  {
    $Script:Port = $Port
  }
  if($UseHTTPS -ne $null)
  {
    Write-Warning "HTTPS is not supported by the Web API."
    $Script:UseHTTPS = $UseHTTPS
  }
  if($Timeout -ne $null)
  {
    if($Timeout.TotalSeconds -le 0)
    {
      Write-Error "Timeout value too low. Please set a value over 0 seconds."
    }
    else
    {
      $Script:DefaultTimeout = $Timeout
    }
  }
  if($Retries -ne $null)
  {
    $Script:DefaultRetries = $Retries
  }
}

Function Get-UcsWebAPIConnectionSetting
{
  $OutputObject = 1 | Select-Object @{Name='Port';Expression={$Script:Port}},@{Name='UseHTTPS';Expression={$Script:UseHTTPS}},@{Name='Timeout';Expression={$Script:DefaultTimeout}},@{Name='Retries';Expression={$Script:DefaultRetries}}
  Return $OutputObject
}

Function Set-UcsWebAPICredential
{
  Param([Parameter(Mandatory)][PsCredential[]]$Credential)
  
  $Script:Credential = $Credential
}

Function Get-UcsWebAPICredential
{
  Return $Script:Credential
}


Function Get-UcsWebConfiguration 
{
  <#
      .SYNOPSIS
      Describe purpose of "Get-UcsWebConfiguration" in 1-2 sentences.

      .DESCRIPTION
      Add a more complete description of what the function does.

      .PARAMETER IPv4Address
      Describe parameter -IPv4Address.

      .PARAMETER IgnoreSources
      Describe parameter -IgnoreSources.

      .PARAMETER IgnoreParameters
      Describe parameter -IgnoreParameters.

      .PARAMETER SourceNameOverride
      Describe parameter -SourceNameOverride.

      .PARAMETER Retries
      Describe parameter -Retries.

      .EXAMPLE
      Get-UcsWebConfiguration -IPv4Address Value -IgnoreSources Value -IgnoreParameters Value -SourceNameOverride Value -Retries Value
      Describe what this call does

      .NOTES
      Place additional notes here.

      .LINK
      URLs to related sites
      The first link is opened by Get-Help -Online Get-UcsWebConfiguration

      .INPUTS
      List of input types that are accepted by this function.

      .OUTPUTS
      List of output types produced by this function.
  #>


  Param([Parameter(Mandatory,HelpMessage = '127.0.0.1',ValueFromPipelineByPropertyName,ValueFromPipeline)][ValidatePattern('^([0-2]?[0-9]{1,2}\.){3}([0-2]?[0-9]{1,2})$')][String[]]$IPv4Address,
    [String[]]$IgnoreSources = ('ParsedHtml', 'RawContent', 'RawContentStream', 'StatusDescription', 'TR69', 'Headers', 'BaseResponse', 'Content', '#comment'),
    [String[]]$IgnoreParameters = ('Length'),
    [Hashtable]$SourceNameOverride = @{
      'CALL_SERVER'   = 'sip'
      'CONFIG_FILES'  = 'config'
      'DEVICE_SETTINGS' = 'device'
      'PHONE_LOCAL'   = 'local'
      'WEB'           = 'web'
    },
    [Int]$Retries = $Script:DefaultRetries
  )
  
  BEGIN {
    $ParameterList = New-Object -TypeName System.Collections.ArrayList
    
  }  PROCESS {
    #Structure:
    <# Foreach IpAddress
        Foreach SourceId (configuration Id)
        Foreach Source in the response (should only be one per)
        Foreach Parameter in each source
    #>
    Foreach ($ThisIPv4Address in $IPv4Address) 
    {
      Try 
      {
        $Results = Invoke-UcsWebRequest -IPv4Address $ThisIPv4Address -ApiEndpoint 'Utilities/configuration/phoneBackup' -ErrorAction Stop
        $Results = [Xml]$Results
        $Results = $Results.PHONE_BACKUP
        $Sources = ($Results |
          Get-Member -ErrorAction Stop |
          Where-Object -Property MemberType -EQ -Value Property |
        Where-Object -Property Name -NotIn -Value $IgnoreSources)
      }
      Catch 
      {
        Write-Debug -Message "Skipping $ThisIPv4Address. $_"
        Continue
      }

      Foreach($Source in $Sources) 
      {
        $SourceName = $Source.Name
        
        #Choose a displayname for the source if it's in the hashtable..
        $SourceDisplayName = $SourceNameOverride[$SourceName]
        if($SourceDisplayName.Length -lt 1) 
        {
          $SourceDisplayName = $SourceName
        }
        $SourceParameters = $Results.$SourceName
      
        Try 
        {
          $ParameterNames = ($SourceParameters |
            Get-Member -ErrorAction Stop |
          Where-Object -Property MemberType -EQ -Value Property).Name
          $ParameterNames = $ParameterNames | Where-Object -FilterScript {
            $_ -notin $IgnoreParameters 
          }
        }
        Catch 
        {
          Write-Debug -Message "We had an issue with $SourceName. Skipping..."
          Continue  
        }
        Foreach ($ParameterName in $ParameterNames) 
        {
          $ParameterValue = $SourceParameters.$ParameterName

          $ThisParameter = $ParameterName | Select-Object -Property @{
            Name       = 'Parameter'
            Expression = {
              $ParameterName
            }
          }, @{
            Name       = 'Value'
            Expression = {
              $ParameterValue
            }
          }, @{
            Name       = 'Source'
            Expression = {
              $SourceDisplayName
            }
          }, @{
            Name       = 'IPv4Address'
            Expression = {
              $ThisIPv4Address
            }
          }
            
          $null = $ParameterList.Add($ThisParameter)
        }
      }
    }
  } END {
    $ParameterList = $ParameterList | Sort-Object -Property IPv4Address, Parameter, Source
    Return $ParameterList
  }
}

Function Get-UcsWebParameter 
{
  <#
      .SYNOPSIS
      Describe purpose of "Get-UcsWebParameter" in 1-2 sentences.

      .DESCRIPTION
      Add a more complete description of what the function does.

      .PARAMETER IPv4Address
      Describe parameter -IPv4Address.

      .PARAMETER Parameter
      Describe parameter -Parameter.

      .EXAMPLE
      Get-UcsWebParameter -IPv4Address Value -Parameter Value
      Describe what this call does

      .NOTES
      Place additional notes here.

      .LINK
      URLs to related sites
      The first link is opened by Get-Help -Online Get-UcsWebParameter

      .INPUTS
      List of input types that are accepted by this function.

      .OUTPUTS
      List of output types produced by this function.
  #>


  Param([Parameter(Mandatory,HelpMessage = '127.0.0.1',ValueFromPipelineByPropertyName,ValueFromPipeline)][ValidatePattern('^([0-2]?[0-9]{1,2}\.){3}([0-2]?[0-9]{1,2})$')][String[]]$IPv4Address,
  [Parameter(Mandatory,HelpMessage = 'A UCS parameter, such as "Up.Timeout."',ValueFromPipelineByPropertyName)][String[]]$Parameter)
  BEGIN {
    $ParameterOutput = New-Object -TypeName System.Collections.ArrayList
  } PROCESS {
    Foreach($ThisIPv4Address in $IPv4Address) 
    {
      $ThisParameterSet = Get-UcsWebConfiguration -IPv4Address $ThisIPv4Address
      
      $null = $ParameterOutput.Add(($ThisParameterSet | Where-Object -Property Parameter -In -Value $Parameter))
    }
  } END {
    Return $ParameterOutput
  }
}

Function Set-UcsWebParameter 
{
  <#
      .SYNOPSIS
      Describe purpose of "Set-UcsWebParameter" in 1-2 sentences.

      .DESCRIPTION
      Add a more complete description of what the function does.

      .PARAMETER IPv4Address
      Describe parameter -IPv4Address.

      .PARAMETER Parameter
      Describe parameter -Parameter.

      .PARAMETER Value
      Describe parameter -Value.

      .PARAMETER PassThru
      Describe parameter -PassThru.

      .EXAMPLE
      Set-UcsWebParameter -IPv4Address Value -Parameter Value -Value Value -PassThru
      Describe what this call does

      .NOTES
      Place additional notes here.

      .LINK
      URLs to related sites
      The first link is opened by Get-Help -Online Set-UcsWebParameter

      .INPUTS
      List of input types that are accepted by this function.

      .OUTPUTS
      List of output types produced by this function.
  #>


  [CmdletBinding(SupportsShouldProcess,ConfirmImpact = 'High')]
  Param([Parameter(Mandatory,HelpMessage = '127.0.0.1',ValueFromPipelineByPropertyName,ValueFromPipeline)][ValidatePattern('^([0-2]?[0-9]{1,2}\.){3}([0-2]?[0-9]{1,2})$')][String[]]$IPv4Address,
    [Parameter(Mandatory,HelpMessage = 'A valid UCS parameter, such as Up.Timeout',ValueFromPipelineByPropertyName)][String]$Parameter,
    [Parameter(Mandatory,HelpMessage = 'A valid value for the specified parameter.')][String]$Value,
  [Switch]$PassThru)
    
  BEGIN {
    $ParameterOutput = New-Object -TypeName System.Collections.ArrayList
    Write-Warning -Message "Not working yet, haven't figured out how to submit the file."
    #TODO: Build a way to send a file.
    #Value accepts boolean values and converts them to something UCS can understand.
    if($Value -eq $true) 
    {
      $Value = '1'
    }
    elseif($Value -eq $false) 
    {
      $Value = '0'
    }
    
    $XMLFileOutput = @"
<?xml version="1.0" encoding="UTF-8" standalone="yes"?>
<PHONE_CONFIG>
<WEB
$Parameter="$Value"
/>
</PHONE_CONFIG>
"@
  } PROCESS {
    Foreach($ThisIPv4Address in $IPv4Address) 
    {
      $ThisResponse = Invoke-UcsWebRequest -IPv4Address $ThisIPv4Address -ApiEndpoint 'form-submit/Utilities/configuration/importFile' -Method Put -ContentType 'application/octet-stream'
      
      $null = $ParameterOutput.Add($ThisResponse)
    }
  } END {
    if($PassThru -eq $true) 
    {
      Return $ParameterOutput
    }
  }
}

Function Get-UcsWebLyncStatus 
{
  <#
      .SYNOPSIS
      Describe purpose of "Get-UcsWebLyncStatus" in 1-2 sentences.

      .DESCRIPTION
      Add a more complete description of what the function does.

      .PARAMETER IPv4Address
      Describe parameter -IPv4Address.

      .EXAMPLE
      Get-UcsWebLyncStatus -IPv4Address Value
      Describe what this call does

      .NOTES
      Place additional notes here.

      .LINK
      URLs to related sites
      The first link is opened by Get-Help -Online Get-UcsWebLyncStatus

      .INPUTS
      List of input types that are accepted by this function.

      .OUTPUTS
      List of output types produced by this function.
  #>


  Param([Parameter(Mandatory,HelpMessage = '127.0.0.1',ValueFromPipelineByPropertyName,ValueFromPipeline)][ValidatePattern('^([0-2]?[0-9]{1,2}\.){3}([0-2]?[0-9]{1,2})$')][String[]]$IPv4Address)

  BEGIN {
    $OutputArray = New-Object -TypeName System.Collections.ArrayList
  } PROCESS {
    Foreach ($ThisIPv4Address in $IPv4Address)
    {
      Try 
      {
        #Actual: http://172.21.84.89/Utilities/LyncStatusXml
        $Results = Invoke-UcsWebRequest -IPv4Address $ThisIPv4Address -ApiEndpoint 'Utilities/LyncStatusXml' -ErrorAction Stop
        $Results = [Xml]$Results
        $Results = $Results.LYNC_STATUS_INFO
        $Results = $Results | Select-Object -Property BOSS_ADMIN, CCCP, EWS, MOH, LYNC_PARAMETERS, O365, QOE, BTOEPCPAIRING, @{
          Name       = 'IPv4Address'
          Expression = {
            $ThisIPv4Address
          }
        }

        $null = $OutputArray.Add($Results)
      }
      Catch 
      {
        Write-Error -Message $_
        Continue #Skip this item.
      }
    }
    
  } END {
    Return $OutputArray
  }
}
Function Get-UcsWebConfigurationOld 
{
  <#
      .SYNOPSIS
      Describe purpose of "Get-UcsWebConfigurationOld" in 1-2 sentences.

      .DESCRIPTION
      Add a more complete description of what the function does.

      .PARAMETER IPv4Address
      Describe parameter -IPv4Address.

      .PARAMETER ConfigId
      Describe parameter -ConfigId.

      .PARAMETER IgnoreSources
      Describe parameter -IgnoreSources.

      .PARAMETER IgnoreParameters
      Describe parameter -IgnoreParameters.

      .PARAMETER Retries
      Describe parameter -Retries.

      .EXAMPLE
      Get-UcsWebConfigurationOld -IPv4Address Value -ConfigId Value -IgnoreSources Value -IgnoreParameters Value -Retries Value
      Describe what this call does

      .NOTES
      Place additional notes here.

      .LINK
      URLs to related sites
      The first link is opened by Get-Help -Online Get-UcsWebConfigurationOld

      .INPUTS
      List of input types that are accepted by this function.

      .OUTPUTS
      List of output types produced by this function.
  #>


  #The difference between this and the other is that this retrieves one at a time - using the backup capability, we get all of the data, all at once.
  Param([Parameter(Mandatory,HelpMessage = '127.0.0.1',ValueFromPipelineByPropertyName,ValueFromPipeline)][ValidatePattern('^([0-2]?[0-9]{1,2}\.){3}([0-2]?[0-9]{1,2})$')][String[]]$IPv4Address,
    [Int[]]$ConfigId = (-1, 1, 2, 5, 6),
    [String[]]$IgnoreSources = ('ParsedHtml', 'RawContent', 'RawContentStream', 'StatusDescription', 'Headers', 'BaseResponse', 'Content', 'All', '#comment'),
    [String[]]$IgnoreParameters = ('Length'),
    [Int]$Retries = $Script:DefaultRetries
  )
  
  BEGIN {
    $ParameterList = New-Object -TypeName System.Collections.ArrayList
    
  }  PROCESS {
    #Structure:
    <# Foreach IpAddress
        Foreach SourceId (configuration Id)
        Foreach Source in the response (should only be one per)
        Foreach Parameter in each source
    #>
    Foreach ($ThisIPv4Address in $IPv4Address) 
    {
      $IsOnline = $false
      $RemainingRetries = $Retries
      Foreach($SourceId in $ConfigId) 
      {
        Try 
        {
          $Results = Invoke-UcsWebRequest -IPv4Address $ThisIPv4Address -ApiEndpoint "Utilities/configuration/exportFile?source=$SourceId" -ErrorAction Stop
          $Results = [Xml]$Results
          $Results = $Results.PHONE_CONFIG
          $Sources = ($Results |
            Get-Member -ErrorAction Stop |
            Where-Object -Property MemberType -EQ -Value Property |
          Where-Object -Property Name -NotIn -Value $IgnoreSources)
          $IsOnline = $true #If we get here, we must have had a valid attempt, so we can set the flag that will prevent the retry mechanism from skipping this device.
        }
        Catch 
        {
          Write-Debug -Message "Skipping config Id $SourceId for $ThisIPv4Address."
          $RemainingRetries--
          if($RemainingRetries -le 0 -and $IsOnline -eq $false) 
          {
            Write-Debug -Message 'No retries remaining'
            Break #Leave the SourceId loop.
          }
          Continue
        }

        Foreach($Source in $Sources) 
        {
          $SourceName = $Source.Name
          $SourceParameters = $Results.$SourceName
      
          Try 
          {
            $ParameterNames = ($SourceParameters |
              Get-Member -ErrorAction Stop |
            Where-Object -Property MemberType -EQ -Value Property).Name
            $ParameterNames = $ParameterNames | Where-Object -FilterScript {
              $_ -notin $IgnoreParameters 
            }
          }
          Catch 
          {
            Write-Debug -Message "We had an issue with $SourceName. Skipping..."
            Continue  
          }
          Foreach ($ParameterName in $ParameterNames) 
          {
            $ParameterValue = $SourceParameters.$ParameterName

            $ThisParameter = $ParameterName | Select-Object -Property @{
              Name       = 'Parameter'
              Expression = {
                $ParameterName
              }
            }, @{
              Name       = 'Value'
              Expression = {
                $ParameterValue
              }
            }, @{
              Name       = 'Source'
              Expression = {
                $SourceName
              }
            }, @{
              Name       = 'SourceId'
              Expression = {
                $SourceId
              }
            }, @{
              Name       = 'IPv4Address'
              Expression = {
                $ThisIPv4Address
              }
            }
            
            $null = $ParameterList.Add($ThisParameter)
          }
        }
      }
    }
  } END {
    $ParameterList = $ParameterList | Sort-Object -Property IPv4Address, Parameter, Source
    Return $ParameterList
  }
}

Function Get-UcsWebAvailableFirmware 
{
  <#
      .SYNOPSIS
      Describe purpose of "Get-UcsWebAvailableFirmware" in 1-2 sentences.

      .DESCRIPTION
      Add a more complete description of what the function does.

      .PARAMETER IPv4Address
      Describe parameter -IPv4Address.

      .PARAMETER CustomServerUrl
      Describe parameter -CustomServerUrl.

      .EXAMPLE
      Get-UcsWebAvailableFirmware -IPv4Address Value
      Describe what this call does

      .EXAMPLE
      Get-UcsWebAvailableFirmware -CustomServerUrl Value
      Describe what this call does

      .NOTES
      Place additional notes here.

      .LINK
      URLs to related sites
      The first link is opened by Get-Help -Online Get-UcsWebAvailableFirmware

      .INPUTS
      List of input types that are accepted by this function.

      .OUTPUTS
      List of output types produced by this function.
  #>


  Param([Parameter(Mandatory,HelpMessage = '127.0.0.1',ValueFromPipelineByPropertyName,ValueFromPipeline)][ValidatePattern('^([0-2]?[0-9]{1,2}\.){3}([0-2]?[0-9]{1,2})$')][String[]]$IPv4Address,
  [Parameter(ParameterSetName = 'CustomServer')][String]$CustomServerUrl = '')
  
  BEGIN {
  
    $AvailableVersions = New-Object -TypeName System.Collections.ArrayList

    if($PSCmdlet.ParameterSetName -eq 'CustomServer') 
    {
      $ServerType = 'customserver'
    }
    else 
    {
      $ServerType = 'plcmserver'
    }
  } PROCESS {
    Foreach ($ThisIPv4Address in $IPv4Address) 
    { 
      #Actual request from a phone: http://10.92.10.48/Utilities/softwareUpgrade/getAvailableVersions?type=plcmserver&_=1498851105686
      $UnixTime = [Math]::Round( (((Get-Date) - (Get-Date -Date 'January 1 1970 00:00:00.00')).TotalSeconds), 0)

      Try 
      {
        #Get the provisioning server info.
        $ServerInfo = Invoke-UcsWebRequest -IPv4Address $ThisIPv4Address -ApiEndpoint 'Utilities/softwareUpgrade/getProvisioningServer' -ErrorAction Stop
        $ServerInfo = $ServerInfo.Split(';')
        $HardwareId = $ServerInfo |
        Where-Object -FilterScript {
          $_ -like 'HARDWARE_ID=*' 
        } |
        Select-Object -First 1
        $HardwareId = $HardwareId.Substring($HardwareId.IndexOf('=') + 1)
        $HardwareRev = $ServerInfo |
        Where-Object -FilterScript {
          $_ -like 'HARDWARE_REV=*' 
        } |
        Select-Object -First 1
        $HardwareRev = $HardwareRev.Substring($HardwareRev.IndexOf('=') + 1)
      }
      Catch 
      {
        $HardwareId = $null
        $HardwareRev = $null
      }
      Try 
      {
        if($PSCmdlet.ParameterSetName -eq 'CustomServer') 
        {
          #If it's a custom server, we have to send the URL to the phone before asking for the update.
          $Body = @{
            CUSTOM_SERVER = "$CustomServerUrl"
          }
          $null = Invoke-UcsWebRequest -IPv4Address $ThisIPv4Address -ApiEndpoint 'form-submit/Utilities/softwareUpgrade/updateCustomServer' -Method Post -Body $Body -ErrorAction -ContentType Stop
        }
        
        $Result = Invoke-UcsWebRequest -IPv4Address $ThisIPv4Address -ApiEndpoint "Utilities/softwareUpgrade/getAvailableVersions?type=$ServerType&_=$UnixTime" -ErrorAction Stop
        
     
        #The response sometimes has garbage before the first tag, so we need to drop it.
        $Result = $Result
        $FirstBracket = $Result.IndexOf('<')
        $Result = $Result.Substring($FirstBracket,$Result.Length - $FirstBracket)
        $Result = ([Xml]$Result).PHONE_IMAGES.REVISION.PHONE_IMAGE
      } Catch 
      {
        Write-Debug -Message "Skipped $ThisIPv4Address due to error $_."
      }
      
      Foreach($Version in $Result) 
      {
        Try 
        {
          $ThisOutput = $Version | Select-Object -Property @{
            Name       = 'FirmwareRelease'
            Expression = {
              $_.Version
            }
          }, @{
            Name       = 'HardwareId'
            Expression = {
              $HardwareId
            }
          }, @{
            Name       = 'HardwareRev'
            Expression = {
              $HardwareRev
            }
          }, @{
            Name       = 'UpdateUri'
            Expression = {
              $_.Path
            }
          }, @{
            Name       = 'IPv4Address'
            Expression = {
              $ThisIPv4Address
            }
          }

          $null = $AvailableVersions.Add($ThisOutput)
        } Catch 
        {
          Write-Debug -Message 'Skipped a version due to a parsing error.'
        }
      }
    }
  } END {
    Return $AvailableVersions
  }
}

Function Update-UcsWebFirmware 
{
  <#
      .SYNOPSIS
      Describe purpose of "Update-UcsWebFirmware" in 1-2 sentences.

      .DESCRIPTION
      Add a more complete description of what the function does.

      .PARAMETER IPv4Address
      Describe parameter -IPv4Address.

      .PARAMETER UpdateUri
      Describe parameter -UpdateUri.

      .EXAMPLE
      Update-UcsWebFirmware -IPv4Address Value -UpdateUri Value
      Describe what this call does

      .NOTES
      Place additional notes here.

      .LINK
      URLs to related sites
      The first link is opened by Get-Help -Online Update-UcsWebFirmware

      .INPUTS
      List of input types that are accepted by this function.

      .OUTPUTS
      List of output types produced by this function.
  #>


  Param([Parameter(Mandatory,HelpMessage = '127.0.0.1',ValueFromPipelineByPropertyName,ValueFromPipeline)][ValidatePattern('^([0-2]?[0-9]{1,2}\.){3}([0-2]?[0-9]{1,2})$')][String[]]$IPv4Address,
  [Parameter(Mandatory,ValueFromPipelineByPropertyName)][String]$UpdateUri)

  BEGIN {
    $StatusResult = New-Object -TypeName System.Collections.ArrayList
  } PROCESS {
    Foreach ($ThisIPv4Address in $IPv4Address) 
    { 
      Try 
      {
        #Actual URL: http://10.92.10.48/form-submit/Utilities/softwareUpgrade/upgrade
        $Body = @{
          URLPath    = "$UpdateUri"
          serverType = 'plcmserver'
        }
        $Result = Invoke-UcsWebRequest -IPv4Address $ThisIPv4Address -ApiEndpoint 'form-submit/Utilities/softwareUpgrade/upgrade' -Body $Body -Method Post -ContentType 'application/x-www-form-urlencoded' -ErrorAction Stop

        $null = $StatusResult.Add($Result)
      } Catch 
      {
        Write-Debug -Message "Skipped $ThisIPv4Address due to error $_."
      }
    }
  } END {
    Return $StatusResult
  }
}

Function Restart-UcsWebPhone 
{
  <#
      .SYNOPSIS
      Describe purpose of "Restart-UcsWebPhone" in 1-2 sentences.

      .DESCRIPTION
      Add a more complete description of what the function does.

      .PARAMETER IPv4Address
      Describe parameter -IPv4Address.

      .PARAMETER Type
      Restart is faster, because it does not fully reinitilize the hardware - it only restarts the application. However, reboot is more complete.

      .EXAMPLE
      Restart-UcsWebPhone -IPv4Address Value -Type Value
      Describe what this call does

      .NOTES
      Place additional notes here.

      .LINK
      URLs to related sites
      The first link is opened by Get-Help -Online Restart-UcsWebPhone

      .INPUTS
      List of input types that are accepted by this function.

      .OUTPUTS
      List of output types produced by this function.
  #>

  [CmdletBinding(SupportsShouldProcess,ConfirmImpact = 'High')]
  Param([Parameter(Mandatory,HelpMessage = '127.0.0.1',ValueFromPipelineByPropertyName,ValueFromPipeline)][ValidatePattern('^([0-2]?[0-9]{1,2}\.){3}([0-2]?[0-9]{1,2})$')][String[]]$IPv4Address,
  [String][ValidateSet('Reboot','Restart')]$Type = 'Reboot')
  
  BEGIN {
    $StatusResult = New-Object -TypeName System.Collections.ArrayList
  } PROCESS {
    Foreach ($ThisIPv4Address in $IPv4Address) 
    { 
      Try 
      {
        #Actual URL: http://10.92.10.48/form-submit/Reboot http://10.92.10.48/form-submit/Restart
        
        $Result = $null
        if($PSCmdlet.ShouldProcess(('{0}' -f $ThisIPv4Address))) 
        {
          $Result = Invoke-UcsWebRequest -IPv4Address $ThisIPv4Address -ApiEndpoint "form-submit/$Type" -Method Post -ContentType 'application/x-www-form-urlencoded' -ErrorAction Stop
        }

        $null = $StatusResult.Add($Result)
      } Catch 
      {
        Write-Debug -Message "Skipped $ThisIPv4Address due to error $_."
        Write-Error -Message "Couldn't restart $ThisIPv4Address."
      }
    }
  } END {
    Return $StatusResult
  }
}

Function Reset-UcsWebConfiguration 
{
  <#
      .SYNOPSIS
      Describe purpose of "Reset-UcsWebConfiguration" in 1-2 sentences.

      .DESCRIPTION
      Add a more complete description of what the function does.

      .PARAMETER IPv4Address
      Describe parameter -IPv4Address.

      .PARAMETER Timeout
      Describe parameter -Timeout.

      .EXAMPLE
      Reset-UcsWebConfiguration -IPv4Address Value -Timeout Value
      Describe what this call does

      .NOTES
      Place additional notes here.

      .LINK
      URLs to related sites
      The first link is opened by Get-Help -Online Reset-UcsWebConfiguration

      .INPUTS
      List of input types that are accepted by this function.

      .OUTPUTS
      List of output types produced by this function.
  #>


  #sets special long timeout for this operation, as it takes a while to reply.
  [CmdletBinding(SupportsShouldProcess,ConfirmImpact = 'High')]
  Param([Parameter(Mandatory,HelpMessage = '127.0.0.1',ValueFromPipelineByPropertyName,ValueFromPipeline)][ValidatePattern('^([0-2]?[0-9]{1,2}\.){3}([0-2]?[0-9]{1,2})$')][String[]]$IPv4Address,
  [Timespan]$Timeout = (New-TimeSpan -Seconds 20))
  
  BEGIN {
    $StatusResult = New-Object -TypeName System.Collections.ArrayList
  } PROCESS {
    Foreach ($ThisIPv4Address in $IPv4Address) 
    { 
      Try 
      {
        #Actual URL: http://10.92.10.160/form-submit/Utilities/restorePhoneToFactory

        if($PSCmdlet.ShouldProcess($ThisIPv4Address,'Reset to factory settings')) 
        {
          $Result = Invoke-UcsWebRequest -IPv4Address $ThisIPv4Address -ApiEndpoint 'form-submit/Utilities/restorePhoneToFactory' -Method Post -ContentType 'application/x-www-form-urlencoded' -Timeout $Timeout -ErrorAction Stop
        }

        $null = $StatusResult.Add($Result)
      } Catch 
      {
        Write-Debug -Message "Skipped $ThisIPv4Address due to error $_."
      }
    }
  } END {
    Return $StatusResult
  }
}

Function Register-UcsWebLyncUser 
{
  <#
      .SYNOPSIS
      Describe purpose of "Register-UcsWebLyncUser" in 1-2 sentences.

      .DESCRIPTION
      Add a more complete description of what the function does.

      .PARAMETER IPv4Address
      Describe parameter -IPv4Address.

      .PARAMETER Extension
      Describe parameter -Extension.

      .PARAMETER PIN
      Describe parameter -PIN.

      .PARAMETER Address
      Describe parameter -Address.

      .PARAMETER Domain
      Describe parameter -Domain.

      .PARAMETER Username
      Describe parameter -Username.

      .PARAMETER Password
      Describe parameter -Password.

      .EXAMPLE
      Register-UcsWebLyncUser -IPv4Address Value
      Describe what this call does

      .EXAMPLE
      Register-UcsWebLyncUser -Extension Value -PIN Value
      Describe what this call does

      .EXAMPLE
      Register-UcsWebLyncUser -Address Value -Domain Value -Username Value -Password Value
      Describe what this call does

      .NOTES
      Place additional notes here.

      .LINK
      URLs to related sites
      The first link is opened by Get-Help -Online Register-UcsWebLyncUser

      .INPUTS
      List of input types that are accepted by this function.

      .OUTPUTS
      List of output types produced by this function.
  #>


  Param([Parameter(Mandatory,HelpMessage = '127.0.0.1',ValueFromPipelineByPropertyName,ValueFromPipeline)][ValidatePattern('^([0-2]?[0-9]{1,2}\.){3}([0-2]?[0-9]{1,2})$')][String[]]$IPv4Address,
    [Parameter(Mandatory,ParameterSetName = 'PIN')][String][ValidatePattern('^\d+$')]$Extension,
    [Parameter(Mandatory,ParameterSetName = 'PIN')][String][ValidatePattern('^\d+$')]$PIN,
    [Parameter(Mandatory,ParameterSetName = 'Credential')][String][ValidatePattern('^\d+$')]$Address,
    [Parameter(Mandatory,ParameterSetName = 'Credential')][String][ValidatePattern('^\d+$')]$Domain,
    [Parameter(ParameterSetName = 'Credential')][String][ValidatePattern('^\d+$')]$Username = '',
    [Parameter(Mandatory,ParameterSetName = 'Credential')][String][ValidatePattern('^\d+$')]$Password
  )
  
  BEGIN {
    $StatusResult = New-Object -TypeName System.Collections.ArrayList
    
    #$EncodedPassword = [System.Web.HttpUtility]::UrlEncode($Password)
    $AuthTypeId = 3 #3 represents PIN authentication.
    if($PSCmdlet.ParameterSetName -eq 'PIN') 
    {
      $AuthTypeId = 3
      $Body = @{
        authType  = "$AuthTypeId"
        extension = "$Extension"
        pin       = "$PIN"
      }
    }
    elseif($PSCmdlet.ParameterSetName -eq 'Credential') 
    {
      $AuthTypeId = 2
      $Body = @{
        authType = "$AuthTypeId"
        address  = "$Address"
        domain   = "$Domain"
        username = "$Username"
        password = "$Password"
      }
    }
  } PROCESS {
    Foreach ($ThisIPv4Address in $IPv4Address) 
    { 
      Try 
      {
        #Actual URL: http://10.92.10.48/form-submit/Settings/lyncSignIn

        $Result = Invoke-UcsWebRequest -IPv4Address $ThisIPv4Address -ApiEndpoint 'form-submit/Settings/lyncSignIn' -Method Post -ContentType 'application/x-www-form-urlencoded' -Body $Body -ErrorAction Stop
         
        $null = $StatusResult.Add($Result)
      } Catch 
      {
        Write-Debug -Message "Skipped $ThisIPv4Address due to error $_."
      }
    }
  } END {
    Return $StatusResult
  }
}

Function Unregister-UcsWebLyncUser 
{
  <#
      .SYNOPSIS
      Describe purpose of "Unregister-UcsWebLyncUser" in 1-2 sentences.

      .DESCRIPTION
      Add a more complete description of what the function does.

      .PARAMETER IPv4Address
      Describe parameter -IPv4Address.

      .EXAMPLE
      Unregister-UcsWebLyncUser -IPv4Address Value
      Describe what this call does

      .NOTES
      Place additional notes here.

      .LINK
      URLs to related sites
      The first link is opened by Get-Help -Online Unregister-UcsWebLyncUser

      .INPUTS
      List of input types that are accepted by this function.

      .OUTPUTS
      List of output types produced by this function.
  #>


  [CmdletBinding(SupportsShouldProcess,ConfirmImpact = 'High')]
  Param([Parameter(Mandatory,HelpMessage = '127.0.0.1',ValueFromPipelineByPropertyName,ValueFromPipeline)][ValidatePattern('^([0-2]?[0-9]{1,2}\.){3}([0-2]?[0-9]{1,2})$')][String[]]$IPv4Address)
  
  BEGIN {
    $StatusResult = New-Object -TypeName System.Collections.ArrayList
  } PROCESS {
    Foreach ($ThisIPv4Address in $IPv4Address) 
    { 
      Try 
      {
        #Actual URL: http://172.21.7.19/form-submit/Settings/lyncSignOut
        
        if($PSCmdlet.ShouldProcess($ThisIPv4Address,'Sign out user')) 
        {
          $Result = Invoke-UcsWebRequest -IPv4Address $ThisIPv4Address -ApiEndpoint 'form-submit/Settings/lyncSignOut' -Method Post -ContentType 'application/x-www-form-urlencoded' -ErrorAction Stop
        
         
          $null = $StatusResult.Add($Result)
        }
      } Catch 
      {
        Write-Debug -Message "Skipped $ThisIPv4Address due to error $_."
      }
    }
  } END {
    Return $StatusResult
  }
}

Function Stop-UcsWebLyncSignIn 
{
  <#
      .SYNOPSIS
      Describe purpose of "Stop-UcsWebLyncSignIn" in 1-2 sentences.

      .DESCRIPTION
      Add a more complete description of what the function does.

      .PARAMETER IPv4Address
      Describe parameter -IPv4Address.

      .EXAMPLE
      Stop-UcsWebLyncSignIn -IPv4Address Value
      Describe what this call does

      .NOTES
      Place additional notes here.

      .LINK
      URLs to related sites
      The first link is opened by Get-Help -Online Stop-UcsWebLyncSignIn

      .INPUTS
      List of input types that are accepted by this function.

      .OUTPUTS
      List of output types produced by this function.
  #>


  Param([Parameter(Mandatory,HelpMessage = '127.0.0.1',ValueFromPipelineByPropertyName,ValueFromPipeline)][ValidatePattern('^([0-2]?[0-9]{1,2}\.){3}([0-2]?[0-9]{1,2})$')][String[]]$IPv4Address)
  BEGIN {
    $StatusResult = New-Object -TypeName System.Collections.ArrayList
  } PROCESS {
    Foreach ($ThisIPv4Address in $IPv4Address) 
    { 
      Try 
      {
        #Actual URL: http://10.92.10.48/form-submit/Settings/lyncCancelSignIn
       
        $Result = Invoke-UcsWebRequest -IPv4Address $ThisIPv4Address -ApiEndpoint 'form-submit/Settings/lyncCancelSignIn' -Method Post -ContentType 'application/x-www-form-urlencoded' -ErrorAction Stop
        
         
        $null = $StatusResult.Add($Result)
      } Catch 
      {
        Write-Debug -Message "Skipped $ThisIPv4Address due to error $_."
      }
    }
  } END {
    Return $StatusResult
  }
}

Function Get-UcsWebAuditLog 
{
  <#
      .SYNOPSIS
      Describe purpose of "Get-UcsWebAuditLogs" in 1-2 sentences.

      .DESCRIPTION
      Add a more complete description of what the function does.

      .PARAMETER IPv4Address
      Describe parameter -IPv4Address.

      .PARAMETER LogType
      Describe parameter -LogType.

      .EXAMPLE
      Get-UcsWebLogs -IPv4Address Value -LogType Value
      Describe what this call does

      .NOTES
      Place additional notes here.

      .LINK
      URLs to related sites
      The first link is opened by Get-Help -Online Get-UcsWebLogs

      .INPUTS
      List of input types that are accepted by this function.

      .OUTPUTS
      List of output types produced by this function.
  #>

  Param([Parameter(Mandatory,HelpMessage = '127.0.0.1',ValueFromPipelineByPropertyName,ValueFromPipeline)][ValidatePattern('^([0-2]?[0-9]{1,2}\.){3}([0-2]?[0-9]{1,2})$')][String[]]$IPv4Address)
  BEGIN {
    $AllResult = New-Object -TypeName System.Collections.ArrayList
  } PROCESS {
    Foreach ($ThisIPv4Address in $IPv4Address) 
    { 
      Try 
      {
        #Actual URL: http://10.92.10.160/Diagnostics/log?value=app&dummyParam=1498860013020
        $UnixTime = [Math]::Round( (((Get-Date) - (Get-Date -Date 'January 1 1970 00:00:00.00')).TotalSeconds), 0)
        $Result = Invoke-UcsWebRequest -IPv4Address $ThisIPv4Address -ApiEndpoint "Diagnostics/log?value=audit&dummyParam=$UnixTime" -ErrorAction Stop
        $SplitString = $Result.Split("`r`n") | Where-Object -FilterScript {
          $_.Length -gt 2 
        }
      } Catch 
      {
        Write-Debug -Message "Skipped $ThisIPv4Address due to error $_."
      }
      
      Foreach ($Line in $SplitString) 
      {
        Try 
        {
          $SplitAuditLine = $Line.Split('|')
          $TimedateString = $SplitAuditLine[0].Trim(' ')
          $MacAddress = $SplitAuditLine[1]
          $Message = $SplitAuditLine[2]
          
          $DateString = $TimedateString.Substring(0,6)
          $YearString = $TimedateString.Substring(($TimedateString.Length - 4))
          $null = $TimedateString -match '\d{2}:\d{2}:\d{2}'
          $TimeString = $Matches[0]
          
          $TimedateString = ('{0} {1} {2}' -f $DateString, $YearString, $TimeString)
          $Date = Get-Date $TimedateString
          
          $ThisResult = 1 | Select-Object -Property @{
            Name       = 'Date'
            Expression = {
              $Date
            }
          }, @{
            Name       = 'MacAddress'
            Expression = {
              $MacAddress
            }
          }, @{
            Name       = 'IPv4Address'
            Expression = {
              $ThisIPv4Address
            }
          }, @{
            Name       = 'Message'
            Expression = {
              $Message
            }
          }
          
          $null = $AllResult.Add($ThisResult)
        } Catch 
        {
          Write-Debug -Message "Skipped $Line due to error $_"
        }
      }
    }
  } END {
    Return $AllResult
  }
}

Function Get-UcsWebLog 
{
  <#
      .SYNOPSIS
      Describe purpose of "Get-UcsWebLogs" in 1-2 sentences.

      .DESCRIPTION
      Add a more complete description of what the function does.

      .PARAMETER IPv4Address
      Describe parameter -IPv4Address.

      .PARAMETER LogType
      Describe parameter -LogType.

      .EXAMPLE
      Get-UcsWebLogs -IPv4Address Value -LogType Value
      Describe what this call does

      .NOTES
      Place additional notes here.

      .LINK
      URLs to related sites
      The first link is opened by Get-Help -Online Get-UcsWebLogs

      .INPUTS
      List of input types that are accepted by this function.

      .OUTPUTS
      List of output types produced by this function.
  #>

  Param([Parameter(Mandatory,HelpMessage = '127.0.0.1',ValueFromPipelineByPropertyName,ValueFromPipeline)][ValidatePattern('^([0-2]?[0-9]{1,2}\.){3}([0-2]?[0-9]{1,2})$')][String[]]$IPv4Address,
  [String][ValidateSet('app','boot')]$LogType = 'app')
  BEGIN {
    $AllResult = New-Object -TypeName System.Collections.ArrayList
  } PROCESS {
    Foreach ($ThisIPv4Address in $IPv4Address) 
    { 
      Try 
      {
        #Actual URL: http://10.92.10.160/Diagnostics/log?value=app&dummyParam=1498860013020
        $UnixTime = [Math]::Round( (((Get-Date) - (Get-Date -Date 'January 1 1970 00:00:00.00')).TotalSeconds), 0)
        $Result = Invoke-UcsWebRequest -IPv4Address $ThisIPv4Address -ApiEndpoint "Diagnostics/log?value=$LogType&dummyParam=$UnixTime" -ErrorAction Stop
        $SplitString = $Result.Split("`r`n") | Where-Object -FilterScript {
          $_.Length -gt 2 
        }
      } Catch 
      {
        Write-Debug -Message "Skipped $ThisIPv4Address due to error $_."
      }
      
      $TheseResults = New-UcsLog -LogString $SplitString -LogType $LogType -IPv4Address $ThisIPv4Address
      Foreach($ThisResult in $TheseResults)
      {
        $null = $AllResult.Add($ThisResult)
      }
    }
  } END {
    Return $AllResult
  }
}

Function Clear-UcsWebLog
{
  Param([Parameter(Mandatory,HelpMessage = '127.0.0.1',ValueFromPipelineByPropertyName,ValueFromPipeline)][ValidatePattern('^([0-2]?[0-9]{1,2}\.){3}([0-2]?[0-9]{1,2})$')][String[]]$IPv4Address,
    [Parameter(Mandatory)][String][ValidateSet('app','boot')]$LogType,
  [Switch]$PassThru)
  BEGIN {
    $AllResult = New-Object -TypeName System.Collections.ArrayList
  } PROCESS {
    Foreach ($ThisIPv4Address in $IPv4Address) 
    { 
      Try 
      {
        #Actual URL: http://10.92.10.160/Diagnostics/log?value=boot&clear=1&dummyParam=1499810229667
        $UnixTime = [Math]::Round( (((Get-Date) - (Get-Date -Date 'January 1 1970 00:00:00.00')).TotalSeconds), 0)
        $Result = Invoke-UcsWebRequest -IPv4Address $ThisIPv4Address -ApiEndpoint "Diagnostics/log?value=$LogType&clear=1&dummyParam=$UnixTime" -ErrorAction Stop

        $null = $AllResult.Add($Result)
      } Catch 
      {
        Write-Debug -Message "Skipped $ThisIPv4Address due to error $_."
      }
    }
  } END {
    if($PassThru -eq $true) 
    {
      Return $AllResult
    }
  }
}

Function Get-UcsWebLyncSignIn 
{
  <#
      .SYNOPSIS
      Describe purpose of "Get-UcsWebLyncSignIn" in 1-2 sentences.

      .DESCRIPTION
      Add a more complete description of what the function does.

      .PARAMETER IPv4Address
      Describe parameter -IPv4Address.

      .EXAMPLE
      Get-UcsWebLyncSignIn -IPv4Address Value
      Describe what this call does

      .NOTES
      Place additional notes here.

      .LINK
      URLs to related sites
      The first link is opened by Get-Help -Online Get-UcsWebLyncSignIn

      .INPUTS
      List of input types that are accepted by this function.

      .OUTPUTS
      List of output types produced by this function.
  #>


  Param([Parameter(Mandatory,HelpMessage = '127.0.0.1',ValueFromPipelineByPropertyName,ValueFromPipeline)][ValidatePattern('^([0-2]?[0-9]{1,2}\.){3}([0-2]?[0-9]{1,2})$')][String[]]$IPv4Address)
  BEGIN {
    $AllOutput = New-Object -TypeName System.Collections.ArrayList
  } PROCESS {
    Foreach($ThisIPv4Address in $IPv4Address) 
    {
      #Signin status is from http://10.92.10.160/Settings/lyncSignInStatus?_=1499803468177
      #Cached credentials from http://10.92.10.160/Settings/lyncCachedCredentials?_=1499803468135
      
      $UnixTime = [Math]::Round( (((Get-Date) - (Get-Date -Date 'January 1 1970 00:00:00.00')).TotalSeconds), 0)
      Try 
      {
        $SigninStatus = Invoke-UcsWebRequest -IPv4Address $ThisIPv4Address -ApiEndpoint "Settings/lyncSignInStatus?_=$UnixTime" -ErrorAction Stop
      }
      Catch 
      {
        Write-Error -Message "Couldn't connect to $ThisIPv4Address."
        Continue
      }
      
      if($SigninStatus -eq 'SIGNED_IN') 
      {
        $SignedIn = $true
      }
      else 
      {
        $SignedIn = $false
      }
      
      $ThisOutput = $SignedIn | Select-Object -Property @{
        Name       = 'Registered'
        Expression = {
          $SignedIn
        }
      }, @{
        Name       = 'IPv4Address'
        Expression = {
          $ThisIPv4Address
        }
      }
      
      if($SignedIn -eq $true) 
      {
        Try 
        {
          $Credentials = Invoke-UcsWebRequest -IPv4Address $ThisIPv4Address -ApiEndpoint "Settings/lyncCachedCredentials?_=$UnixTime" -ErrorAction Stop
        }
        Catch 
        {
          Write-Error -Message "Couldn't retrieve sign-in information for $ThisIPv4Address."
          Continue
        }
        $Credentials = ConvertFrom-Json -InputObject $Credentials
        
        if($Credentials.isUsingCfg -eq 'false') 
        {
          $IsUsingCfg = $false
        }
        else 
        {
          $IsUsingCfg = $true
        }
       
        $ThisOutput = $ThisOutput | Select-Object -Property *, @{
          Name       = 'SipAddress'
          Expression = {
            $Credentials.address
          }
        }, @{
          Name       = 'Domain'
          Expression = {
            $Credentials.domain
          }
        }, @{
          Name       = 'Username'
          Expression = {
            $Credentials.user
          }
        }, @{
          Name       = 'Extension'
          Expression = {
            $Credentials.extension
          }
        }, @{
          Name       = 'IsUsingConfig'
          Expression = {
            $IsUsingCfg
          }
        }
        
        if($Credentials.Extension.Length -gt 0) 
        {
          #We're using PIN auth and therefore aren't using Domain or User.
          $ThisOutput = $ThisOutput | Select-Object -Property * -ExcludeProperty Domain, Username
        }
        else 
        {
          #We're using user auth and therefore aren't using Domain or User.
          $ThisOutput = $ThisOutput | Select-Object -Property * -ExcludeProperty Extension
        }
        
        
      }
      $null = $AllOutput.Add($ThisOutput) #Add to the collection.
    }
  } END {
    Return $AllOutput
  }
}

Function Get-UcsWebDeviceInfo 
{
  <#
      .SYNOPSIS
      Describe purpose of "Get-UcsWebPhoneInfo" in 1-2 sentences.

      .DESCRIPTION
      The "LastReboot" parameter may be inaccurate because it is computed based on logs instead of directly provided by the API - usually no more than 12 hours off.

      .PARAMETER IPv4Address
      Describe parameter -IPv4Address.

      .EXAMPLE
      Get-UcsWebPhoneInfo -IPv4Address Value
      Describe what this call does

      .NOTES
      Place additional notes here.

      .LINK
      URLs to related sites
      The first link is opened by Get-Help -Online Get-UcsWebPhoneInfo

      .INPUTS
      List of input types that are accepted by this function.

      .OUTPUTS
      List of output types produced by this function.
  #>


  Param([Parameter(Mandatory,HelpMessage = '127.0.0.1',ValueFromPipelineByPropertyName,ValueFromPipeline)][ValidatePattern('^([0-2]?[0-9]{1,2}\.){3}([0-2]?[0-9]{1,2})$')][String[]]$IPv4Address)
  
  BEGIN {
    $AllPhoneInfo = New-Object -TypeName System.Collections.ArrayList
  } PROCESS {
    Foreach($ThisIPv4Address in $IPv4Address) 
    {
      Try 
      {
        #http://10.92.10.160/home.htm
        $ThisResult = Invoke-UcsWebRequest -IPv4Address $ThisIPv4Address -ApiEndpoint 'home.htm' -ErrorAction Stop
      }
      Catch 
      {
        Write-Error -Message "Couldn't connect to $ThisIPv4Address."
        Continue
      }
      
      
      $Content = $ThisResult
      
      $Matches = $null
      $null = $Content -match "(?<=UCS_software_version`">\r*\n*\s*)[^<]+"
      $FirmwareRelease = $Matches[0].Trim("`r`n ")
      
      $Matches = $null
      $null = $Content -match "(?<=phoneModelInformationTd`">\r*\n*\s*)[^<]+"
      $Model = $Matches[0].Trim("`r`n ")
      
      $Matches = $null
      $null = $Content -match '(?<=\s*)\d{4}-\d{5}-\d{3}'
      $HardwareId = $Matches[0].Trim("`r`n ")
      
      $Matches = $null
      $null = $Content -match "(?<=$HardwareId\sRev:)\w"
      $HardwareRev = $Matches[0].Trim("`r`n ")
      
      $Matches = $null
      $null = $Content -match '[a-f0-9]{2}:[a-f0-9]{2}:[a-f0-9]{2}:[a-f0-9]{2}:[a-f0-9]{2}:[a-f0-9]{2}'
      $MacAddress = (($Matches[0].Trim("`r`n ")).Replace(':','')).ToLower()
      
      $LastReboot = (Get-UcsWebLastReboot -IPv4Address $ThisIPv4Address -ErrorAction SilentlyContinue).LastReboot
      
      $ThisResult = 1 | Select-Object -Property @{
        Name       = 'MacAddress'
        Expression = {
          $MacAddress
        }
      }, @{
        Name       = 'Model'
        Expression = {
          $Model
        }
      }, @{
        Name       = 'HardwareId'
        Expression = {
          $HardwareId
        }
      }, @{
        Name       = 'HardwareRev'
        Expression = {
          $HardwareRev
        }
      }, @{
        Name       = 'FirmwareRelease'
        Expression = {
          $FirmwareRelease
        }
      }, @{
        Name       = 'LastReboot'
        Expression = {
          $LastReboot
        }
      }, @{
        Name       = 'IPv4Address'
        Expression = {
          $ThisIPv4Address
        }
      }
      $null = $AllPhoneInfo.Add($ThisResult)
    }
  } END {
    Return $AllPhoneInfo
  }
}

Function Get-UcsWebProvisioningInfo {
  Param([Parameter(Mandatory,HelpMessage = '127.0.0.1',ValueFromPipelineByPropertyName,ValueFromPipeline)][ValidatePattern('^([0-2]?[0-9]{1,2}\.){3}([0-2]?[0-9]{1,2})$')][String[]]$IPv4Address)
  
  BEGIN
  {
    $OutputObject = New-Object System.Collections.ArrayList
  }
  PROCESS
  {
    Foreach ($ThisIPv4Address in $IPv4Address)
    {
      $ProvisioningServer = $null
      Try
      {
        $Config = $null
        $Matches = $null
        $ProvUserType = Get-UcsWebParameter -IPv4Address $ThisIPv4Address -Parameter ('device.prov.user','device.prov.serverType')
        $ProvUser = $ProvUserType | Where-Object Parameter -eq "device.prov.user"
        $ProvType = $ProvUserType | Where-Object Parameter -eq "device.prov.serverType"
        $Logs = Get-UcsWebLog -IPv4Address $ThisIPv4Address -LogType app -ErrorAction Stop
        $Logs = $Logs | Where-Object Message -like "Provisioning server address is*" | Select-Object -Last 1
        $null = $Logs.Message -match '(?<=Provisioning server address is).+(?=\.)'
        if($Logs.Count -eq 0) {
          #Try something else if the first thing didn't work.
          $Logs = $Logs | Where-Object Message -like "Prov|Server*is unresponsive" | Select-Object -Last 1
          $null = $Logs.Message -match "(?<=Prov|Server ').+(?='.+)"
        }
        $ProvisioningServer = $Matches[0].Trim(' ')
        
        $ThisOutput = $ProvisioningServer | Select-Object @{Name="ProvServerAddress";Expression={$ProvisioningServer}},@{Name="ProvServerUser";Expression={$ProvUser.Value}},@{Name="ProvServerType";Expression={$ProvType.Value}},@{Name="IPv4Address";Expression={$ThisIPv4Address}}
        $null = $OutputObject.Add($ThisOutput)
      }
      Catch
      {
        Write-Error "Couldn't get provisioning server for $ThisIPv4Address"
      }
    }
  }
  END
  {
    Return $OutputObject
  }
}

Function Get-UcsWebLastReboot {
  Param([Parameter(Mandatory,HelpMessage = '127.0.0.1',ValueFromPipelineByPropertyName,ValueFromPipeline)][ValidatePattern('^([0-2]?[0-9]{1,2}\.){3}([0-2]?[0-9]{1,2})$')][String[]]$IPv4Address,
  [Timespan]$BootLogClockSkew = (New-Timespan -Seconds 300))
  Begin
  {
    $Reboots = New-Object System.Collections.ArrayList
  }
  Process
  {
    Foreach($ThisIPv4Address in $IPv4Address)
    {
      Try
      {
        foreach($LogType in ('app','boot')) {
          $LastReboot = $null
          
        
          if($Model -like "*Trio*" -and $LogType -eq 'boot') {
            Write-Debug "Skipping boot logs for $ThisIPv4Address because it was detected as $Model."
            Continue
          }

          $TheseLogs = Get-UcsWebLog -IPv4Address $ThisIPv4Address -LogType $LogType -ErrorAction Stop
          if($LogType -eq 'boot')
          {
            Foreach($Log in $TheseLogs)
            {
              #Apply a clock skew to the boot logs to correct for differences between reported times from logs and the REST API official time.
              $Log.DateTime = $Log.DateTime + $BootLogClockSkew
            }
          }

          $Logs = $TheseLogs | Sort-Object -Property DateTime
          $FirstLog = $Logs | Where-Object DateTime -ne $null | Where-Object Level -eq "*" | Where-Object Message -like "Initial log entry.*" | Select-Object -Last 1
          $LastReboot = $FirstLog.DateTime

          if($LastReboot -ne $null) {
            Break #Leave this loop, we've found the lastreboot.
          }
        }
      }
      Catch
      {
        $LastReboot = $null
        Write-Error "Couldn't get a LastReboot for $ThisIPv4Address. Error was $_."        
      }
      
      if($LastReboot -ne $null) {
        $ThisOutput = $LastReboot | Select-Object @{Name="LastReboot";Expression={$LastReboot}},@{Name="IPv4Address";Expression={$ThisIPv4Address}}
        $null = $Reboots.Add($ThisOutput)
      }
    }
  }
  End
  {
    Return $Reboots
  }
}

Function Reset-UcsWebParameter {
  Param([Parameter(Mandatory,HelpMessage = '127.0.0.1',ValueFromPipelineByPropertyName,ValueFromPipeline)][ValidatePattern('^([0-2]?[0-9]{1,2}\.){3}([0-2]?[0-9]{1,2})$')][String[]]$IPv4Address,
  [Parameter(Mandatory,HelpMessage = 'A UCS parameter, such as "Up.Timeout."',ValueFromPipelineByPropertyName)][String[]]$Parameter)
  
  Begin
  {
  }
  Process
  {
    Foreach($ThisIPv4Address in $IPv4Address)
    {
      Try
      {
        $FormBody = $null
        Foreach($ThisParameter in $Parameter)
        {
          $FormBody += @{$ThisParameter=$null}
        }
        
        #http://10.92.10.48/form-submit/resetToDefault
        $Result = Invoke-UcsWebRequest -IPv4Address $ThisIPv4Address -ApiEndpoint 'form-submit/resetToDefault' -Method Post -Body $FormBody -ContentType 'application/x-www-form-urlencoded' -ErrorAction Stop
      }
      Catch
      {
        Write-Error "Couldn't reset parameter on $ThisIPv4Address."
      }
    }
  }
  End
  {
  }
}
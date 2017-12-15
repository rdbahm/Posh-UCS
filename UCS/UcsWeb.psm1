Function Get-UcsWebConfiguration 
{
  Param([Parameter(Mandatory,HelpMessage = '127.0.0.1',ValueFromPipelineByPropertyName,ValueFromPipeline)][ValidatePattern('^([0-2]?[0-9]{1,2}\.){3}([0-2]?[0-9]{1,2})$')][String[]]$IPv4Address,
    [String[]]$IgnoreSources = ('ParsedHtml', 'RawContent', 'RawContentStream', 'StatusDescription', 'Headers', 'BaseResponse', 'Content', '#comment'),
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

Function Get-UcsWebFirmware 
{
  <#
      .PARAMETER Latest
      Returns only the most recent firmware available for this phone model.
  #>
  Param([Parameter(Mandatory,HelpMessage = '127.0.0.1',ValueFromPipelineByPropertyName,ValueFromPipeline)][ValidatePattern('^([0-2]?[0-9]{1,2}\.){3}([0-2]?[0-9]{1,2})$')][String[]]$IPv4Address,
    [Parameter(ParameterSetName = 'CustomServer')][String]$CustomServerUrl = '',
    [Switch]$Latest,
    [Timespan]$Timeout = (New-TimeSpan -Seconds 30)
  )
  
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
        
        $Result = Invoke-UcsWebRequest -IPv4Address $ThisIPv4Address -ApiEndpoint "Utilities/softwareUpgrade/getAvailableVersions?type=$ServerType&_=$UnixTime" -ErrorAction Stop -Timeout $Timeout
        
     
        #The response sometimes has garbage before the first tag, so we need to drop it.
        $Result = $Result
        $FirstBracket = $Result.IndexOf('<')
        $Result = $Result.Substring($FirstBracket,$Result.Length - $FirstBracket)
        $Result = ([Xml]$Result).PHONE_IMAGES.REVISION.PHONE_IMAGE
      } Catch 
      {
        Write-Debug -Message "Skipped $ThisIPv4Address due to error $_."
      }
      
      if($Latest -eq $true)
      {
        Write-Debug ('{0} results were returned but the -Latest parameter was included, so dropping all but last one.' -f $Result.Count)
        $Result = $Result | Select-Object -Last 1
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
  [CmdletBinding(SupportsShouldProcess,ConfirmImpact = 'High')]
  Param([Parameter(Mandatory,HelpMessage = '127.0.0.1',ValueFromPipelineByPropertyName,ValueFromPipeline)][ValidatePattern('^([0-2]?[0-9]{1,2}\.){3}([0-2]?[0-9]{1,2})$')][String[]]$IPv4Address,
  [Parameter(Mandatory,ValueFromPipelineByPropertyName)][ValidatePattern('^https?://.+$')][String]$UpdateUri)

  BEGIN {
    $StatusResult = New-Object -TypeName System.Collections.ArrayList
  } PROCESS {
    Foreach ($ThisIPv4Address in $IPv4Address) 
    { 
      Try 
      {
        #Actual URL: http://10.92.10.48/form-submit/Utilities/softwareUpgrade/upgrade
        <#$Body = @{
            URLPath    = "$UpdateUri"
            serverType = 'plcmserver'
        }#>
        $EncodedURL = [System.Web.HttpUtility]::UrlEncode($UpdateUri) 
        $Body = ('URLPath={0}&serverType={1}' -f $EncodedURL,'plcmserver')
        
        if($PSCmdlet.ShouldProcess(('{0}' -f $ThisIPv4Address))) 
        {
          $Result = Invoke-UcsWebRequest -IPv4Address $ThisIPv4Address -ApiEndpoint 'form-submit/Utilities/softwareUpgrade/upgrade' -Body $Body -Method Post -ContentType 'application/x-www-form-urlencoded' -ErrorAction Stop
        }
        
        $null = $StatusResult.Add($Result)
      } Catch 
      {
        Write-Error -Message "Skipped $ThisIPv4Address due to error $_" -Category DeviceError
      }
    }
  } END {
    Return $StatusResult
  }
}

Function Restart-UcsWebPhone 
{
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

Function Get-UcsWebLyncSignInStatus
{
  Param([Parameter(Mandatory,HelpMessage = '127.0.0.1',ValueFromPipelineByPropertyName,ValueFromPipeline)][ValidatePattern('^([0-2]?[0-9]{1,2}\.){3}([0-2]?[0-9]{1,2})$')][String[]]$IPv4Address,
    [String][ValidateSet('None','SignedOut','SignedIn','SigningOut','SigningIn','PasswordChanged')]$WaitFor = 'None',
    [Int][ValidateRange(1,3600)]$TimeoutSeconds = 120
  )
  
  BEGIN
  {
    $ResultOutput = New-Object System.Collections.ArrayList
    $StartTime = Get-Date #Used for calculation of "WaitFor"
    $EndTime = $StartTime.AddSeconds($TimeoutSeconds)
  }
  
  PROCESS
  {
    Foreach($ThisIPv4Address in $IPv4Address)
    {
      $ContinueWaiting = $true
      
      While($ContinueWaiting -eq $true)
      {
        Try
        {
          $UnixTime = [Math]::Round( (((Get-Date) - (Get-Date -Date 'January 1 1970 00:00:00.00')).TotalSeconds), 0)
          $SigninStatus = Invoke-UcsWebRequest -IPv4Address $ThisIPv4Address -ApiEndpoint "Settings/lyncSignInStatus?_=$UnixTime" -ErrorAction Stop
        }
        Catch
        {
          $SigninStatus = "UNAVAILABLE"
          Write-Error "Could not get sign in status for $ThisIPv4Address."
          $ContinueWaiting = $false #Regardless of our type, this is a dead-end, so stop checking.
        }
        
        #Check if we've met what we're waiting for.
        if($WaitFor -eq 'None')
        {
          $ContinueWaiting = $false
        }
        elseif($WaitFor -eq 'SignedOut' -and $SigninStatus -eq 'UNREGISTERED')
        {
          $ContinueWaiting = $false
        }
        elseif($WaitFor -eq 'SignedIn' -and $SigninStatus -eq 'SIGNED_IN')
        {
          $ContinueWaiting = $false
        }
        elseif($WaitFor -eq 'SigningIn' -and $SigninStatus -eq 'SIGNING_IN')
        {
          $ContinueWaiting = $false
        }
        elseif($WaitFor -eq 'SigningOut' -and $SigninStatus -eq 'SIGNING_OUT')
        {
          $ContinueWaiting = $false
        }
        elseif($WaitFor -eq 'PasswordChanged' -and $SigninStatus -eq 'PASS_CHANGED')
        {
          $ContinueWaiting = $false
        }
        elseif( (Get-Date) -gt $EndTime)
        {
          $ContinueWaiting = $false
          Write-Warning "Timeout expired while waiting for $ThisIPv4Address."
        }
        else
        {
          Start-Sleep -Seconds 1 #Delay to prevent hammering the phone too much.
        }
      }
      
      $ThisOutput = $ThisIPv4Address | Select-Object @{Name="IPv4Address";Expression={$ThisIPv4Address}},@{Name="SignInStatus";Expression={$SigninStatus}}
      $null = $ResultOutput.Add($ThisOutput)
    }
  }
  
  END
  {
    Return $ResultOutput
  }
}
Function Register-UcsWebLyncUser 
{
  Param([Parameter(Mandatory,HelpMessage = '127.0.0.1',ValueFromPipelineByPropertyName,ValueFromPipeline)][ValidatePattern('^([0-2]?[0-9]{1,2}\.){3}([0-2]?[0-9]{1,2})$')][String[]]$IPv4Address,
    [Parameter(Mandatory,ParameterSetName = 'PIN')][String][ValidatePattern('^\d+$')]$Extension,
    [Parameter(Mandatory,ParameterSetName = 'PIN')][String][ValidatePattern('^\d+$')]$PIN,
    [Parameter(Mandatory,ParameterSetName = 'Credential')][String][ValidatePattern('^\d+$')]$Address,
    [Parameter(Mandatory,ParameterSetName = 'Credential')][String][ValidatePattern('^\d+$')]$Domain,
    [Parameter(ParameterSetName = 'Credential')][String][ValidatePattern('^\d+$')]$Username = '',
    [Parameter(Mandatory,ParameterSetName = 'Credential')][String][ValidatePattern('^\d+$')]$Password,
    [Switch]$Force,
    [Switch]$Wait
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
        $CurrentSignInStatus = Get-UcsWebLyncSignInStatus -IPv4Address $ThisIPv4Address -ErrorAction SilentlyContinue
        $DoSignIn = $true
        
        if($CurrentSignInStatus.SignInStatus -eq "SIGNED_IN")
        {
          if($Force)
          {
            Write-Warning "$ThisIPv4Address was signed in. Sign-in has been unregistered."
            Unregister-UcsWebLyncUser -IPv4Address $ThisIPv4Address -Wait -Confirm:$false
          }
          else
          {
            Write-Error "$ThisIPv4Address is currently signed in. Use the -Force flag to automatically unregister current sign-ins."
            $DoSignIn = $false
          }
        }
        elseif($CurrentSignInStatus.SignInStatus -eq "SIGNING_IN")
        {
          if($Force)
          {
            Write-Warning "$ThisIPv4Address was in the process of signing in. Sign-in has been cancelled and restarted."
            Stop-UcsWebLyncSignIn -IPv4Address $ThisIPv4Address
            $null = Get-UcsWebLyncSignInStatus -IPv4Address $ThisIPv4Address -WaitFor SignedOut
          }
          else
          {
            Write-Error "$ThisIPv4Address is currently in the process of signing in. Use the -Force flag to automatically cancel current sign-ins."
            $DoSignIn = $false
          }
        }
        
        #TODO: There are other states, like PASS_CHANGED, that would need sign out/sign in. Perhaps we can look for "Not SIGNED_OUT."

        if($DoSignIn)
        {
          $Result = Invoke-UcsWebRequest -IPv4Address $ThisIPv4Address -ApiEndpoint 'form-submit/Settings/lyncSignIn' -Method Post -ContentType 'application/x-www-form-urlencoded' -Body $Body -ErrorAction Stop
          $null = $StatusResult.Add($ThisIPv4Address) #We only get to this line if the first line doesn't fail.
        }
      } Catch 
      {
        Write-Error -Message "Skipped $ThisIPv4Address due to error $_."
      }

      if($Result -ne '' -and $Result -ne $null)
      {
        #The phone usually responds with nothing if a sign-in succeeds.
        Write-Error ('Sign-in request failed for {0} with error ''{1}.''' -f $ThisIPv4Address,$Result)
      }
    }
  } END {
    if($Wait)
    {
      #The wait flag allows a user to instruct the script to wait to exit until all phones have signed in.
      #As a nice side effect, this also allows us to throw an error if the sign-in fails for any reason.
      #We batch together all the phones to minimize wait time - this way, if you have 100 phones, there may be almost no waiting.
      Foreach ($ThisIPv4Address in $StatusResult)
      {
        $SigninStatus = $null
        Do
        {
          if($SigninStatus -ne $null)
          {
            Start-Sleep -Seconds 1 #After the first check, back off the phone a little.
          }
          $UnixTime = [Math]::Round( (((Get-Date) - (Get-Date -Date 'January 1 1970 00:00:00.00')).TotalSeconds), 0)
          $SigninStatus = Invoke-UcsWebRequest -IPv4Address $ThisIPv4Address -ApiEndpoint "Settings/lyncSignInStatus?_=$UnixTime" -ErrorAction Stop
        }
        While ($SigninStatus -eq 'SIGNING_IN')
      
        if($SigninStatus -eq 'UNREGISTERED')
        {
          Write-Error ('Sign-in request failed for {0}. Bad credentials?' -f $ThisIPv4Address) -Category AuthenticationError
        }
      }
    }
  }
}

Function Unregister-UcsWebLyncUser 
{
  [CmdletBinding(SupportsShouldProcess,ConfirmImpact = 'High')]
  Param([Parameter(Mandatory,HelpMessage = '127.0.0.1',ValueFromPipelineByPropertyName,ValueFromPipeline)][ValidatePattern('^([0-2]?[0-9]{1,2}\.){3}([0-2]?[0-9]{1,2})$')][String[]]$IPv4Address,
  [Switch]$Wait)
  
  BEGIN {
    $SuccessPhones = New-Object -TypeName System.Collections.ArrayList
  } PROCESS {
    Foreach ($ThisIPv4Address in $IPv4Address) 
    { 
      Try 
      {
        #Actual URL: http://172.21.7.19/form-submit/Settings/lyncSignOut
        
        if($PSCmdlet.ShouldProcess($ThisIPv4Address,'Sign out user')) 
        {
          $Result = Invoke-UcsWebRequest -IPv4Address $ThisIPv4Address -ApiEndpoint 'form-submit/Settings/lyncSignOut' -Method Post -ContentType 'application/x-www-form-urlencoded' -ErrorAction Stop
        }
      }
      Catch 
      {
        Write-Error -Message "Skipped $ThisIPv4Address due to error $_."
      }
         
      
      if($Result -ne "SIGNING_OUT")
      {
        Write-Error ('Sign-out request failed for {0} with error ''{1}.''' -f $ThisIPv4Address,$Result)
      }
      else
      {
        $null = $SuccessPhones.Add($ThisIPv4Address)
      }
    }
  } END {
    if($Wait)
    {
      $null = Get-UcsWebLyncSignInStatus -IPv4Address $SuccessPhones -WaitFor SignedOut
    }
  }
}

Function Stop-UcsWebLyncSignIn 
{
  Param([Parameter(Mandatory,HelpMessage = '127.0.0.1',ValueFromPipelineByPropertyName,ValueFromPipeline)][ValidatePattern('^([0-2]?[0-9]{1,2}\.){3}([0-2]?[0-9]{1,2})$')][String[]]$IPv4Address)
  BEGIN {
    $StatusResult = New-Object -TypeName System.Collections.ArrayList
  } PROCESS {
    Foreach ($ThisIPv4Address in $IPv4Address) 
    { 
      Try 
      {
        #Actual URL: http://10.92.10.48/form-submit/Settings/lyncCancelSignIn

        $SigninStatus = Get-UcsWebLyncSignInStatus -IPv4Address $ThisIPv4Address

        if($SigninStatus.SignInStatus -eq 'SIGNING_IN')
        {
          $Result = Invoke-UcsWebRequest -IPv4Address $ThisIPv4Address -ApiEndpoint 'form-submit/Settings/lyncCancelSignIn' -Method Post -ContentType 'application/x-www-form-urlencoded' -ErrorAction Stop
        }
        else
        {
          Write-Error "No sign-in to cancel for $ThisIPv4Address."
        }
      } Catch 
      {
        Write-Debug -Message "Skipped $ThisIPv4Address due to error $_."
      }
      
      if($Result -ne '' -and $Result -ne $null)
      {
        Write-Error ('Sign-in cancel request failed for {0} with error ''{1}''' -f $ThisIPv4Address,$Result)
      }
    }
  } END {
  }
}

Function Get-UcsWebAuditLog 
{
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
      $null = $Content -match "\d+\.\d+\.\d+\.\d{4,}[A-Z]?" #We're looking for the specific format of the software version string, which seems to always be 1.1.1.1234 or similar.
      $FirmwareRelease = $Matches[0]
      
      $Matches = $null
      $null = $Content -match '(?<=\n\s*)(\w+\s)+\d+'
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
        #Remove a leading FTP:// or similar.
        $ProvisioningServer = $ProvisioningServer.Replace('/','\') #Make all slashes the same.
        $ProvisioningServerIndex = $ProvisioningServer.LastIndexOf('\') + 1
        if($ProvisioningServerIndex -gt 0)
        {
          $ProvisioningServer = $ProvisioningServer.Substring($ProvisioningServerIndex)
        }
        
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
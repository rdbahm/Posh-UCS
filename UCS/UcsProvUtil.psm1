
Function Import-UcsProvFile
{
  Param(
    [Parameter(Mandatory)][Alias('Path','Filename')][String]$FilePath,
    [ValidateSet('None','Misc','Log','Override','Contact','License','Profile','Call','Corefile')][String]$Type = 'None',
    [Nullable[Int]]$ProvServerIndex = $null
  )
  
  <#Example file to download:
      192.168.1.50/example/file.txt
      COMPUTERNAME/FILEPATH

      We disallow slashes in a computer name to prevent ftp:// etc from being included.
  #>
  
  Begin
  {
    $ProvisioningConfig = Get-UcsProvConfig
    
    if($ProvServerIndex -ne $null)
    {
      #If manually specified, we want to force which provisioning server to use. Mostly used for recursion.
      $ProvisioningConfig = $ProvisioningConfig | Where-Object -Property ProvServerIndex -EQ -Value $ProvServerIndex
    }
    
    $OutputContent = ''
    $TypeMapping = @{
      None     = ''
      Misc     = 'MISC_FILES'
      Log      = 'LOG_FILE_DIRECTORY'
      Override = 'OVERRIDES_DIRECTORY'
      Contact  = 'CONTACTS_DIRECTORY'
      License  = 'LICENSE_DIRECTORY'
      Profile  = 'USER_PROFILES_DIRECTORY'
      Call     = 'CALL_LISTS_DIRECTORY'
      Corefile = 'COREFILE_DIRECTORY'
    }
    $ThisType = $TypeMapping[$Type]

  }
  Process
  {
    $SaveLocation = ''
    $ThisSuccess = $false

    Foreach ($ThisServer in $ProvisioningConfig)
    {
      Write-Debug -Message ('{2}: Trying {0} for {1}.' -f $ThisServer.DisplayName, $ThisServer.ProvServerAddress, $PSCmdlet.MyInvocation.MyCommand.Name)
      
      if($Type -ne 'None')
      {
        #We must start by getting the location of the file in question if mode hasn't been set to "none."
        #We mostly need 'none' available for recursion.
        Try 
        {
          $MasterConfigContent = Import-UcsProvFile -FilePath '000000000000.cfg' -Type None -ProvServerIndex $ThisServer.ProvServerIndex -ErrorAction Stop
          $MasterConfig = Convert-UcsProvMasterConfig -Content $MasterConfigContent.Content -ErrorAction Stop
          $ThisDirectory = ($MasterConfig.$ThisType).Trim('/\ ')
        
          if($ThisDirectory.length -gt 0)
          {
            $Working = $FilePath
            $Parent = $Working | Split-Path -Parent
            $Leaf = $Working | Split-Path -Leaf
            $Working = Join-Path -Path $ThisDirectory -ChildPath $Leaf
            if($Parent.Length -gt 0)
            {
              $Working = Join-Path -Path $Parent -ChildPath $Working
            }
            $FilePath = $Working
          }
        }
        Catch 
        {
          Write-Error -Message ('Couldn''t get master config file for {0}.' -f $ThisServer.DisplayName) -ErrorAction Stop
        }
      }
      
      Try
      {
        Switch($ThisServer.ProvServerType)
        {
          'FileSystem'
          {
            $FullPath = Join-Path -Path $ThisServer.ProvServerAddress -ChildPath $FilePath
            
            if($ThisServer.Credential -ne $null)
            {
              $Item = Copy-Item -Path $FullPath -Destination $env:TEMP -Credential $ThisServer.Credential -PassThru -ErrorAction Stop
            }
            else
            {
              $Item = Copy-Item -Path $FullPath -Destination $env:TEMP -PassThru -ErrorAction Stop
            }
            
            $SaveLocation = $Item.FullName
            $ThisSuccess = $true
          }
          'FTP'
          {
            $SaveLocation = Get-UcsProvFTPFile -Address $ThisServer.ProvServerAddress -Filename $FilePath -Credential $ThisServer.Credential -ErrorAction Stop
            $ThisSuccess = $true
          }
          Default
          {
            Write-Debug -Message ('{2}: {0} is not supported for this operation.' -f $ThisServer.DisplayName, $ThisServer.ProvServerAddress, $PSCmdlet.MyInvocation.MyCommand.Name)
          }
        }
      }
      Catch
      {
        Write-Debug -Message ('{2}: Encountered an error using {0} provisioning protocol with {1}.' -f $ThisServer.DisplayName, $ThisServer.ProvServerAddress, $PSCmdlet.MyInvocation.MyCommand.Name)
        Write-Debug -Message ('{0}: {1}' -f $ThisServer.DisplayName, $_)
      }
      
      if($ThisSuccess -eq $true)
      {
        #We succeeded, so we don't have to retry.
        $OutputObject = Get-Item -Path $SaveLocation
        $OutputObject = $OutputObject | Select-Object -Property BaseName, Name, Directory, FullName, Extension, @{
          Name       = 'Content'
          Expression = {
            Get-Content -Path $SaveLocation
          }
        }, @{
          Name       = 'ProvServerIndex'
          Expression = {
            $ThisServer.ProvServerIndex
          }
        }
        $OutputContent = $OutputObject
        
        Break
      }
    }
    
    if($ThisSuccess -ne $true)
    {
      Write-Error -Message "Couldn't get file $FilePath." -ErrorAction Stop
    }
  }
  End
  {
    Return $OutputContent
  }
}

Function Import-UcsProvCallLogXml 
{
  <#
      .SYNOPSIS
      Describe purpose of "Import-UcsProvCallLogXml" in 1-2 sentences.

      .DESCRIPTION
      Add a more complete description of what the function does.

      .PARAMETER Filename
      Describe parameter -Filename.

      .EXAMPLE
      Import-UcsProvCallLogXml -Filename Value
      Describe what this call does

      .NOTES
      Place additional notes here.

      .LINK
      URLs to related sites
      The first link is opened by Get-Help -Online Import-UcsProvCallLogXml

      .INPUTS
      List of input types that are accepted by this function.

      .OUTPUTS
      List of output types produced by this function.
  #>


  <#
      SYNOPSIS
      Takes a filename, reads the file, and parses its call information.
  #>
  Param(
    [Parameter(Mandatory,HelpMessage = 'Add help message for user')][String[]]$Path
  )
  BEGIN {
    $AllCalls = New-Object -TypeName System.Collections.ArrayList
    $Count = 0
  } PROCESS {
    Foreach($ThisFilename in $Path) 
    {
      $Count++
      Try
      {
        $File = Get-Item $Path
        $Content = $File | Get-Content
      }
      Catch
      {
        Write-Error -Message "Couldn't get content for $Path."
        Continue
      }

      $Error.Clear()
      $Content = $Content.Replace('&','&amp;') #Polycom's log files don't conform to XML specifications and can include & within a set of XML tags. This mitigates that.
      $Content = [Xml] $Content

      if($Error.Count -ne 0) 
      {
        Write-Warning -Message ('Error detected in file.')
        Continue
      }

      $LastUpdated = Get-Date -Date $Content.Saved.Trim('@ --')
      Write-Debug -Message ('{0} was last updated {1}.' -f $ThisFilename, $LastUpdated.ToShortDateString())

      Foreach ($Call in $Content.callList.call) 
      {
        $Duration = (Convert-UcsProvDuration -Duration $Call.duration)

        $ThisSource = Format-UcsProvCallData -CallData $Call.Source -Type Address
        $ThisDestination = Format-UcsProvCallData -CallData $Call.Destination -Type Address
        $ThisConnection = Format-UcsProvCallData -CallData $Call.Connection -Type Address

        $ThisSourceName = Format-UcsProvCallData -CallData $Call.Source -Type Name
        $ThisDestinationName = Format-UcsProvCallData -CallData $Call.Destination -Type Name
        $ThisConnectionName = Format-UcsProvCallData -CallData $Call.Connection -Type Name

        if($Call.direction -eq 'In') 
        {
          $RemotePartyName = $ThisSourceName
          $RemotePartyNumber = $ThisSource
          $LocalPartyName = $ThisDestinationName
          $LocalPartyNumber = $ThisDestination
        }
        else 
        {
          $RemotePartyName = $ThisDestinationName
          $RemotePartyNumber = $ThisDestination
          $LocalPartyName = $ThisSource
          $LocalPartyNumber =  $ThisSourceName
        }
        
        $ThisCall = New-UcsCallObject -Type $Call.direction `
          -RemotePartyName $RemotePartyName `
          -RemotePartyNumber $RemotePartyNumber `
          -LocalPartyName $LocalPartyName `
          -LocalPartyNumber $LocalPartyNumber `
          -ConnectionName $ThisConnectionName `
          -ConnectionNumber $ThisConnection `
          -CallState Log `
          -Protocol $Call.Protocol `
          -LineID $Call.Line `
          -StartTime (Get-Date -Date $Call.StartTime) `
          -Duration $Duration `
          -MacAddress $File.BaseName.Substring(0, 12) `
          -Disposition $Call.Disposition `
          -IsLog `
          -ExcludeNullProperties

        #Missing: Connection

        $null = $AllCalls.Add($ThisCall)
      }
    }
  } END {
    Return $AllCalls
  }
}
Function Convert-UcsProvMasterConfig 
{
  <#
      .SYNOPSIS
      Reads the Polycom 000000000000.cfg file from disk and returns an easily-parsed listing of key information.

      .DESCRIPTION
      Add a more complete description of what the function does.

      .PARAMETER Filename
      Describe parameter -Filename.

      .EXAMPLE
      Get-UcsProvMasterConfig -Filename Value
      Describe what this call does

      .NOTES
      Place additional notes here.

      .LINK
      URLs to related sites
      The first link is opened by Get-Help -Online Get-UcsProvMasterConfig

      .INPUTS
      List of input types that are accepted by this function.

      .OUTPUTS
      List of output types produced by this function.
  #>

  Param(
    [Parameter(Mandatory,HelpMessage = 'The content of the master config file')][String[]]$Content
  )
  Try 
  {
    [XML]$XMLContent = $Content
  }
  Catch 
  {
    Write-Error ('Unable to read content from master config file.')
    Break
  }

  $Output = $XMLContent.Application | Select-Object -Property APP_FILE_PATH, CONFIG_FILES, MISC_FILES, LOG_FILE_DIRECTORY, OVERRIDES_DIRECTORY, CONTACTS_DIRECTORY, LICENSE_DIRECTORY, USER_PROFILES_DIRECTORY, CALL_LISTS_DIRECTORY, COREFILE_DIRECTORY

  Return $Output
}

Function Format-UcsProvCallData 
{
  <#
      .SYNOPSIS
      Takes source, destination, or connection, then returns a collection of the result, address only.

      .DESCRIPTION
      Supporting function for Import-UcsCallLogXml.

      .PARAMETER CallData
      CallData as passed from Import-UcsCallLogXml.

      .PARAMETER Type
      "Address" or "Name"

      .EXAMPLE
      Format-UcsCallData -CallData Value -Type Value
      Describe what this call does

      .NOTES
      Place additional notes here.

      .LINK
      URLs to related sites
      The first link is opened by Get-Help -Online Format-UcsCallData

      .INPUTS
      List of input types that are accepted by this function.

      .OUTPUTS
      List of output types produced by this function.
  #>

  Param($CallData, [Parameter(Mandatory,HelpMessage = 'Add help message for user')][ValidateSet('Address','Name')][String]$Type)

  $Output = New-Object -TypeName System.Collections.ArrayList

  Foreach($Data in $CallData) 
  {
    if($Type -eq 'Address') 
    {
      $ThisAddress = $Data.Address
    }
    elseif($Type -eq 'Name') 
    {
      $ThisAddress = $Data.Name
    }
        
    $ThisAddress = $ThisAddress.Replace('sip:','') #Remove SIP to improve data consistency.
    $ThisAddress = $ThisAddress.Replace('tel:','') #Remove TEL to improve data consistency.

    $ThisAddress = $ThisAddress.Replace('&apos;',"'") #Convert escaped apostrophe to an apostrophe.
    $ThisAddress = $ThisAddress.Replace('&quot;',"`"") #Convert escaped quote to an quote.

    $null = $Output.Add($ThisAddress)
  }

  if($Output.Count -eq 0) 
  {
    $Output = $null
  }
  elseif($Output.Count -eq 1) 
  {
    $Output = $Output[0]
  }

  Return $Output
}

Function Convert-UcsProvDuration 
{
  <#
      .SYNOPSIS
      Gets a call duration from output, then converts to a timespan.

      .DESCRIPTION
      Takes a pattern such as P1DT5H6M3 and converts to a standard timespan.

      .PARAMETER Duration
      Duration string from UCS.

      .EXAMPLE
      Convert-UcsDuration -Duration Value
      Returns a timespan object.

      .OUTPUTS
      Timespan
  #>
  Param ([Parameter(Mandatory,HelpMessage = 'P1DT5H6M3')][ValidatePattern('^P(\d+D)?(T)?(\d+H)?(\d+M)?(\d+S)?$')][String]$Duration)

  $Seconds = 0
  $Minutes = 0
  $Hours = 0
  $Days = 0

  $Done = $false

  #The format seems to be roughly:
  #P1DT1H1M1S for a time including days
  #PT1H1M1S for a time not including days.
  #The parser doesn't care as long as the number is suffixed with the right letter, so we can drop P and T.
  $Trimmed = $Duration.Replace('P','')
  $Trimmed = $Trimmed.Replace('T','')

  While ($Done -eq $false) 
  {
    $NextIndex = $Trimmed.IndexOfAny('DHMS') #Find the first time indicator.
    $NextValue = $Trimmed.Substring(0,$NextIndex) #This is the next numerical value.

    if($Trimmed[$NextIndex] -eq 'D') 
    {
      $Days = $NextValue
    }
    elseif($Trimmed[$NextIndex] -eq 'H') 
    {
      $Hours = $NextValue
    }
    elseif($Trimmed[$NextIndex] -eq 'M') 
    {
      $Minutes = $NextValue
    }
    elseif($Trimmed[$NextIndex] -eq 'S') 
    {
      $Seconds = $NextValue
    }
    else 
    {
      $Done = $true
    }

    if( (($Trimmed.Length) - 1) -gt $NextIndex) 
    {
      #Only use this codepath if there's anything left.
      $Trimmed = $Trimmed.Substring($NextIndex + 1) #Cut off the beginning and start again.
    }
    else 
    {
      $Done = $true
    }
  }

  return New-TimeSpan -Days $Days -Hours $Hours -Minutes $Minutes -Seconds $Seconds
}

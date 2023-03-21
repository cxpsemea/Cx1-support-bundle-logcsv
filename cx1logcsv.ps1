param (
    [Parameter(Position=0,mandatory=$true)]
    [string]$path
)

if ( -not (Test-Path -path $path) ) {
    Write-Host "Path $path does not exist."
    exit
}

$emptyJSON = @"
{
    '*':  null
}
"@ 

function FixTime( $time ) {
    # why is this necessary
    if ( $time -match '(\d+/\w+/\d+):(\d+:\d+:\d+).*' ) {
        return "$($Matches[1]) $($Matches[2])"
    }
    if ( $time -match '(\d+\-\d+\-\d+)T(\d+:\d+:\d+.\d+)Z' ) {
        return "$($Matches[1]) $($Matches[2])"
    }
    if ( $time -match '(\d+\-\d+\-\d+)T(\d+:\d+:\d+)Z' ) {
        return "$($Matches[1]) $($Matches[2])"
    }
    if ( $time -match '(\d+\-\d+\-\d+)T(\d+:\d+:\d+)\+.*' ) {
        return "$($Matches[1]) $($Matches[2])"
    }
    if ( $time -match '\d+\.\d+' ) {
        return Get-Date -Date ((Get-Date -Date "01-01-1970") + ([System.TimeSpan]::FromSeconds($time))) -Format "yyyy-MM-dd hh:mm:ss"
    }
    return $time
}

function ParseInput( $line ) {
    $js = ($line | ConvertFrom-Json)
    
    $loglevel = "$($js.level)"
    if ( $loglevel -eq "" ) {
        $loglevel = "$($js.status)"
    }

    $logtime = "$($js.time)"
            
    if ( $logtime -eq "" ) {
        $logtime = "$($js.'@timestamp')"
    }
    if ( $logtime -eq "" ) {
        $logtime = "$($js.timestamp)"
    }
    if ( $logtime -eq "" ) {
        $logtime = "$($js.ts)"
    }
            
    $logapp = "$($js.app)"
    if ( $logapp -eq "" ) {
        $logapp = "$($js.appName)"
    }
    if ( $logapp -eq "" ) {
        $logapp = "$($js.componentName)"
    }
    if ( $logapp -eq "" ) {
        $logapp = "$($js.serviceName)"
    }
    if ( $logapp -eq "" ) {
        $logapp = "$($js.issuingService)"
    }
    if ( $logapp -eq "" ) {
        $logapp = "$($js.name)"
    }
    if ( $logapp -eq "" ) {
        $logapp = "$($js.Namespace)"
    }

    $logmsg = "$($js.msg)"
            
    if ( $logmsg -eq "" ) {
        $logmsg = "$($js.message)"
    }
    if ( $logmsg -eq "" ) {
        $logmsg = "$($js.Message)"
    }

    $logerr = "$($js.err)"
            
    if ( $logerr -eq "" ) {
        $logerr = "$($js.error)"
    } 
    if ( $js.correlationId -ne $null ) {
        $logcorrelationId = "$($js.correlationId)"
    }
    if ( $js.stacktrace -ne $null ) {
        $logstacktrace = "$($js.stacktrace)"
    }


    $trimmed = $js | Select-Object -Property * -ExcludeProperty level,time,appName,msg,err,correlationId,stacktrace,app,issuingService,componentName,message,error,serviceName,`@timestamp,timestamp,ts,name,Namespace,status

    $logextra = ($trimmed | ConvertTo-Json).Replace( "`"", "'" )
    if ( $logextra -eq $emptyJSON ) {
        $logextra = ""
    }

    if ( $logapp -eq "" ) {
        #Write-Host "Empty logapp for: $js"
        $logapp = $file_svc
    }

    if ( $logmsg -ne $null ) {
        $logmsg = $logmsg.Replace( """", "'" )
    }
    if ( $logstacktrace -ne $null ) {
        $logstacktrace = $logstacktrace.Replace( """", "'" )
    }
    if ( $logerr -ne $null ) {
        $logerr = $logerr.Replace( """", "'" )
    }

    $logtime = FixTime $logtime
            
    return """$loglevel"";""$logtime"";""$logapp"";""$logmsg"";""$logerr"";""$logcorrelationId"";""$logstacktrace"";""$logextra"";"
}


function ParseLogs() {
    Write-Host "Searching for all *.log files in $path"
    Write-Host " - Parsed log output will be in: $path.csv"
    Write-Host " - Unparsed output will be in: $path-err.csv"

    "sep=;" | out-file "$path-err.csv"

    $files = @{}
    $fileCount = 0
    $lineCount = 0
    $jsonLineCount = 0
    $webLineCount = 0

    Get-ChildItem -Path .\ -Include "*.log" -Recurse | foreach-object {
        $fileCount ++

        $lines = Get-Content -Path $_.FullName
        $lineCount += $lines.Length
    
        $file = $_.FullName.Replace( $pwd, "" )
        $file_svc = $_.BaseName

        #if ( $file -match "ast-swagger*" ) {
        #if ( $jsonLineCount -lt 100 ) {

        $jsonLines = @()

        $lastLine = ""
        $unparseable = 0

        $lines | foreach-object {
            if ($_.Length -gt 1) {
                if ($_.SubString(0,1) -eq "{") {
                    $jsonLineCount++
                    if ($_.SubString($_.Length-1,1) -eq "}") {
                        $line = $_.Replace( "scanId", "scanID" )
                        $jsonLine = ParseInput $line
                        $jsonLines += $jsonLine
                    } else {
                        Write-Host "Line isn't complete json? $_"
                    }
                                    #     time          request     status         host        useragent  
                } elseif( $_ -match '^.*\[([^\]]+)\]\s+"([^"]+)"\s+(\d+)\s+\d+\s+"([^"]+)"\s+"([^"]+)".*' ) {
                    $webLineCount++
                    $logerr = [int]$Matches[3]
                    $logmsg = $Matches[2]
                    $logtime = $Matches[1]
                    $loglevel = "info"
                    if ( $logerr -ge 400 ) {
                        $loglevel = "error"
                    }
                    $logcorrelationId = $Matches[4] #close enough
                    $logtime = FixTime $logtime

                    $jsonLines += """$loglevel"";""$logtime"";""$logapp"";""$logmsg"";""$logerr"";""$logcorrelationId"";""$logstacktrace"";""$logextra"";"
                } else {
                    "$file;$_" | out-file "$path-err.csv" -Append
                    $unparseable ++
                }
            }
        }
        
        $files[$file] = $jsonLines
    
        #} 
    }

    Write-Host "Read $fileCount files with $lineCount lines of which $jsonLineCount were json & $webLineCount were web text logs"

    "sep=;" | out-file "$path.csv"

    "file;level;time;app;msg;err;correlationId;stack;extra;" | Out-File "$path.csv" -Append

    $files.Keys | foreach-object {
        $k = $_
        $files[$k] | foreach-object {
            $js = $_
            "$k;$js;" | out-file "$path.csv" -Append 
        }
    }
}

function ParseYaml() {
    Write-Host "Searching for *.yaml in $path"

    $astVersion = ""

    Get-ChildItem -Path .\ -Include "*.yaml" -Recurse | foreach-object {
        $file = $_.FullName
        if ( $file -match 'microservices\.ast\.checkmarx\.com.*ast\.yaml' ) {
            $yaml = ConvertFrom-Yaml (Get-Content -Path $_.FullName -Raw)
            $yaml | foreach-object {
                $obj = $_
                if ( $obj.metadata.name -eq "ast-core-host-webapp" ) {
                    $obj.spec.envirmentVariablesUnencrypted | foreach-object {
                        if ( $_.Key -eq 'AST_VERSION' ) {
                            $astVersion = "$($_.Value) created $($obj.metadata.creationTimestamp)"
                        }
                    }
                    
                }
            }
        }
    }

    Write-Host "AST version: $astVersion"
}

ParseLogs
ParseYaml
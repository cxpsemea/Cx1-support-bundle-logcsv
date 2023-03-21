param (
    [Parameter(Mandatory)]
    $path,
    $start = "1970-01-01 00:00:00", 
    $end = "2030-01-01 00:00:00", #let's hope we don't need it by then
    [bool]$errlog = $false,
    $filter = ""
)

$startTime = (Get-Date -Date $start -Format "yyyy-MM-dd hh:mm:ss")
$endTime = (Get-Date -Date $end -Format "yyyy-MM-dd hh:mm:ss")
Write-Host "Running with options:`n`t`$path: $path (directory containing logs)`n`t`$start = $start (logs since time)`n`t`$end = $end (logs until time)`n`t`$errlog = $errlog (output unparsed data to file)`n`t`$filter = $filter (regex to match log filenames for inclusion)"

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
        $time = "$($Matches[1]) $($Matches[2])"
    } elseif ( $time -match '(\d+\-\d+\-\d+)T(\d+:\d+:\d+.\d+)Z' ) {
        $time = "$($Matches[1]) $($Matches[2])"
    } elseif ( $time -match '(\d+\-\d+\-\d+)T(\d+:\d+:\d+)Z' ) {
        $time = "$($Matches[1]) $($Matches[2])"
    } elseif ( $time -match '(\d+\-\d+\-\d+)T(\d+:\d+:\d+)\+.*' ) {
        $time = "$($Matches[1]) $($Matches[2])"
    } elseif ( $time -match '\d+\.\d+' ) {
        return Get-Date -Date ((Get-Date -Date "01-01-1970") + ([System.TimeSpan]::FromSeconds($time))) -Format "yyyy-MM-dd hh:mm:ss"
    }
    return (Get-Date -Date $time -Format "yyyy-MM-dd hh:mm:ss")
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

    if ( $logtime -eq "" ) {
        return ""
    }

    $logtime = FixTime $logtime
    
    if ( [datetime]$logtime -lt [datetime]$startTime -or [datetime]$logtime -gt [datetime]$endTime ) {        
        #Write-Host " - skip $logtime not in [ $startTime, $endTime ]"
        return "skip"
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
            
    return """$loglevel"";""$logtime"";""$logapp"";""$logmsg"";""$logerr"";""$logcorrelationId"";""$logstacktrace"";""$logextra"";"
}


function ParseLogs() {
    Write-Host "Searching for all *.log files in $path"
    Write-Host " - Parsed log output will be in: $path.csv"
    if ( $errlog ) {
        Write-Host " - Unparsed output will be in: $path-err.csv"
    } else {
        Write-Host " - Unparsed output will summarized in $path-err.csv, but will not be written anywhere. Use argument `$errlog = `$true"
    }

    "sep=;" | out-file "$path-err.csv"

    "sep=;" | out-file "$path.csv"
    "file;level;time;app;msg;err;correlationId;stack;extra;" | Out-File "$path.csv" -Append

    #$files = @{}
    $fileCount = 0
    $lineCount = 0
    $jsonLineCount = 0
    $webLineCount = 0

    Get-ChildItem -Path .\ -Include "*.log" -Recurse | foreach-object {
        $fileCount ++
    
        $file = $_.FullName.Replace( $pwd, "" )
        $file_svc = $_.BaseName

        $current = 0
        $unparseable = 0

        if ( $filter -eq "" -or $file -match $filter ) {

            $lines = Get-Content -Path $_.FullName
            $lineCount += $lines.Length
            Write-Host " - $file ($($lines.Length) lines)"

            if ( $lines.Length -gt 0 ) {
                $lines | foreach-object {
                    $current++
                    if ( $current % 500 -eq 0 ) {
                        Write-Host "   - $current / $($lines.Length)"
                    }
                    if ($_.Length -gt 1) {
                        if ($_.SubString(0,1) -eq "{") {
                            $jsonLineCount++
                            if ($_.SubString($_.Length-1,1) -eq "}") {
                                $line = $_.Replace( "scanId", "scanID" )
                                $jsonLine = ParseInput $line
                                if ( $jsonLine -eq "" ) {
                                    if ( $errlog ) {
                                        "$file;$_" | out-file "$path-err.csv" -Append
                                    }
                                } elseif ( $jsonLine -ne "skip" ) {
                                    "$file;$jsonLine"| out-file "$path.csv" -Append 
                                }
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
    
                            if ( [datetime]$logtime -ge [datetime]$startTime -and [datetime]$logtime -le [datetime]$endTime ) {        
                                "$file;""$loglevel"";""$logtime"";""$logapp"";""$logmsg"";""$logerr"";""$logcorrelationId"";""$logstacktrace"";""$logextra"";" | out-file "$path.csv" -Append 
                            }

                            
                        } else {
                            if ( $errlog ) {
                                "$file;$_" | out-file "$path-err.csv" -Append
                            }
                            $unparseable ++
                        }
                    }
                }

                if ( $unparseable -gt 0 -and -not $errlog ) {
                    "$file;$unparseable lines" | out-file "$path-err.csv" -Append
                }
            }
        } else {
            Write-Host " - $file (skipped due to filter argument)"
        }
    }

    Write-Host "Read $fileCount files with $lineCount lines of which $jsonLineCount were json & $webLineCount were web text logs"

}

function ParseYaml() {
    Write-Host "Searching for *.yaml in $path"

    $astVersion = ""

    Get-ChildItem -Path .\ -Include "*.yaml" -Recurse | foreach-object {
        $file = $_.FullName.Replace( $pwd, "" )
        Write-Host " - $file"
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
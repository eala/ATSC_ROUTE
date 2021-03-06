#!/bin/bash

#This script is intended to transform static MPD generated by MP4BOX to dynamic. This is done by:
#1- Change type="static" to type="dynamic"
#2- Add availabilityStartTime at MPD level
#3- Set Period ids incrementally in case they are empty

if [ $# -ne 4 ]
then
	echo "Usage: ./ConvertMPD.sh ContentDirectory MPDName ASTDelayFromNow slsFrequencyDuration #EncodingSymbolsPerPacket VideoSegmentDuration AudioSegmentDuration VideoOutputFile AudioOutputFile"
	exit
fi 

period=1;	#This is used to incrementally set periods in MPD
toPrint=1;	#This is used to generate new MPD with only 1 video and 1 audio representation.
		#It assumes that audio and video are in seperate adaptation sets
		
videoChunks="Chunks_Video_Inband_Init.txt"		#This file is going to be used to generate FLUTE input file which determines 
									#how to send each segment (i.e. delay before each block of bytes
audioChunks="Chunks_Audio_Inband_Init.txt"

cd $1
	
									
#Get CurrentTime
timenow=$(($(date +'%s * 1000000 + %-N / 1000')))
#Get time with offset, which would be ast timestamp
ast=`awk -v timenow=$timenow -v delta=$3 'BEGIN { OFMT = "%.0f"; print timenow + delta*1000000 }'`
astsec=`awk -v ast=$ast 'BEGIN { print int(ast/1000000) }'`
astfracsec=`awk -v ast=$ast 'BEGIN { printf "%.4d" , int(ast/100) - int(ast/1000000)*10000 }'`
#Get date in UTC (This is the time reference used by the DASH reference client
AST=$(date -u +"%Y-%m-%dT%T" -d @"$astsec")"."$astfracsec

echo $AST

filename=$(basename "$2")
extension="${filename##*.}"
filename="${filename%.*}"

dynamicMPDName=$filename"_Dynamic."$extension

php ../StaticToDynamic.php MPD=$2 uMPD=$dynamicMPDName ASTUNIX=$ast AST=$AST"Z" slsFrequencyDuration=$4
#Copy this in case you want to run only in the command line
#php ../StaticToDynamic.php MPD=MultiRate.mpd uMPD=MultiRate_Dynamic.mpd ASTUNIX=0 AST=0 slsFrequencyDuration=100

cd -

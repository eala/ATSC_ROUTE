#!/bin/bash

#This script arranges data generated by the FLUTE sender and receiver (For example, maps start of fdt instance reception time to that of relevant segment)
#as well as data generated by the DASH reference client (saved in sqlite database)

if [ $# -ne 4 ]
then
	echo "Usage: ./OrganizeData.sh Send_Log.txt Rcv_Log.txt SqliteDB OutputVideoLog"
	exit
fi

if [ ! -e $1 -o ! -e $2 -o ! -e $3 ]; then
	echo "One of the input files does not exist"
	echo "Exiting"
exit
fi

#Varibales
fps=24;								#This is the number of frames per second used in video encoding.
segmentDuration=2;						#This is used to determine segment number from media presentation time which is stored in decoded frames"
vidSegNam="BBB_720_1M_video_"					#This is media template used for video segments in MPD.
vidSegExt=".mp4"						#This is extension of video segment files.
tmpFile="tmpFile.txt";
sqlExportFile="ExportSql.txt";
outFile="outFile.txt";
outFile2="out2File.txt";
FinalFile="FinalFile.txt";
videoFile=$4;

if [ -e $tmpFile ]; then
	rm $tmpFile
fi

if [ -e $sqlExportFile ]; then
	rm $sqlExportFile
fi

if [ -e $outFile ]; then
	rm $outFile
fi

if [ -e $videoFile ]; then
	rm $videoFile
fi

#Exporting SQL table into a text file. Key and values are space seperated
echo "Exporting Browser Local Storage"
sqlite3 -list -separator " " $3 "select * from ItemTable;" > $sqlExportFile


FDTNum=0										#index of FDT. Example, if 0 means FDT was the first one received. 1 means that this FDT was the second
												#one received and so on

a=$(awk -v fdtFound=0 -v numObjectsRcvd=$FDTNum -v tmpFile=$tmpFile '{if (index($0,"file") > 0) {print $2" "$3 > tmpFile; numObjectsRcvd++;fdtFound=0} else if (index($0,"FDTReception") > 0 && fdtFound == 0) {print $2;fdtFound=1}} END{print numObjectsRcvd}' $2)

reception=($a);		#a[0] contains all printed values of $2. This step separates the values into the different indices of reception array

echo ${reception[${#reception[@]} - 1]};		#Last element in the array contains the number of objects received
												#Note that FDT reception does not necessarily mean object reception since FDT could be duplicate
												
while [ $FDTNum -lt ${reception[${#reception[@]} - 1]} ]
do

#First awk obtains data pertaining to receiver and second awk appends it to data pertaining to sender

latest=$(awk -v reception=${reception[$FDTNum]} -v record=$(( $FDTNum + 1 )) 'NR==record {print reception" "$0}' $tmpFile)

awk -v record=$(( $FDTNum + 4 )) -v latest="$latest" -v outFile=$outFile 'NR==record {print $0" "latest >> outFile }' $1

FDTNum=$(($FDTNum + 1))

done

#It is time to combine HTML5 local storage data with that of FLUTE
FDTNum=0										#reuse variable
alternate=0
while true
do
b=$(awk -v record=$(( $FDTNum + 1 )) 'NR==record {print $0}' $sqlExportFile)
htmlrecord=($b);
#echo ${#htmlrecord[@]}
if [ ${#htmlrecord[@]} -eq 0 ]; then
	echo "Done with HTML local storage data"
	break

elif [ "${htmlrecord[0]}" == "DecodedFrames" ]; then
	decodedFrames=($b)
fi

#echo ${htmlrecord[1]} ${htmlrecord[2]} ${htmlrecord[3]} ${htmlrecord[4]} ${htmlrecord[5]} ${htmlrecord[6]}
if [ $alternate -eq 0 ]; then 
	awk -v segment=${htmlrecord[0]} -v data="${htmlrecord[1]} ${htmlrecord[2]} ${htmlrecord[3]} ${htmlrecord[4]} ${htmlrecord[5]} ${htmlrecord[6]}" -v outFile=$outFile2 '{ if (index(segment,$1) > 0) {print $0" "data > outFile} else {print $0> outFile}}' $outFile
fi

if [ $alternate -eq 1 ]; then 
	awk -v segment=${htmlrecord[0]} -v data="${htmlrecord[1]} ${htmlrecord[2]} ${htmlrecord[3]} ${htmlrecord[4]} ${htmlrecord[5]} ${htmlrecord[6]}" -v outFile=$outFile '{if (index(segment,$1) > 0) {print $0" "data > outFile} else {print $0> outFile}}' $outFile2
fi

if [ $alternate -eq 0 ]; then 
	alternate=1
else
	alternate=0
fi
FDTNum=$(($FDTNum + 1))
done

if [ $alternate -eq 0 ]; then 
	cp $outFile $FinalFile
else
	cp $outFile2 $FinalFile
fi

#The code below uses the value of decoded frames key in the local storage
#The format is....DecodedFrames ActualTime MediaPresentationTime DecodedFrames ActualTime MediaPresentationTime DecodedFrames...etc
index=2
segmentNum=1			#MediaPresentationTime corresponding to a segment is: (segmentNum -1)*segmentDuration --> segmentNum*segmentDuration  (Assuming fixed segment durations)
startAtRecord=1

while [ $index -lt ${#decodedFrames[@]} ]
do

	cond=$(echo "${decodedFrames[$index]}>$(($(($segmentNum - 1))*$segmentDuration))" | bc -l)			#bc is needed since bash does not support floating numbers

	if [ $cond -eq 1 ]; then

		presentationTime=$(printf "%0.f" "$(echo "${decodedFrames[$index]}*1000" | bc -l)")				#This is the media presentation time with msec precision (usec precision is rounded)
	
		correction=${presentationTime:$((${#presentationTime}-3)):3}									#Use the msec part and subtract it from actual time to get the "exact time" at which the segment started being displayed
	
		startTime=$(echo "${decodedFrames[$index-1]}-$correction" | bc -l)								#Get "actual" starting time of the next segment
		#echo $segmentNum" "${decodedFrames[$index-1]}" "$correction" "$startTime 
	
		#startAtRecord=$(awk -v startAtRecord=$startAtRecord  -v startTime=$startTime -v currSeg=$videoSegNam$segmentNum$vidSegExt -v videoFile=$videoFile 'NR>=startAtRecord {if (index($0,currSeg) > 0) {print $0" "startTime >> videoFile;print NR}}' $FinalFile)
		#echo $startTime
		startAtRecord=$(awk -v startAtRecord=$startAtRecord  -v startTime=$startTime -v currSeg=$vidSegNam$segmentNum$vidSegExt -v videoFile=$videoFile 'NR>=startAtRecord {if (index($0,currSeg) > 0) {print $0" "startTime >> videoFile; print NR}}' $FinalFile)
	
		segmentNum=$(($segmentNum + 1))																	
	fi


	index=$(($index + 3))
done

rm $tmpFile $outFile $outFile2 $FinalFile
echo "Done"

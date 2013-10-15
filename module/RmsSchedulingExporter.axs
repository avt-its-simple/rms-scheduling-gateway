MODULE_NAME='RmsSchedulingExporter'(dev vdvRms, long locationIds[], char locationNames[][], char filename[])


#define INCLUDE_RMS_EVENT_CLIENT_ONLINE_CALLBACK
#define INCLUDE_RMS_EVENT_CLIENT_OFFLINE_CALLBACK
#define INCLUDE_SCHEDULING_ACTIVE_RESPONSE_CALLBACK
#define INCLUDE_SCHEDULING_NEXT_ACTIVE_RESPONSE_CALLBACK
#define INCLUDE_SCHEDULING_ACTIVE_UPDATED_CALLBACK
#define INCLUDE_SCHEDULING_NEXT_ACTIVE_UPDATED_CALLBACK


#include 'RmsApi'
#include 'RmsSchedulingApi';
#include 'RmsSchedulingEventListener';
#include 'XmlUtil'


define_type

structure bookingTracker {
	RmsLocation location;
	RmsEventBookingResponse activeBooking;
	RmsEventBookingResponse nextBooking;
}


define_variable

constant integer MAX_LOCATIONS = 10;

constant long POLL_TL = 1;
constant integer POLL_INTERVAL = 5; // minutes

volatile bookingTracker bookings[MAX_LOCATIONS];


define_function log(char msg[]) {
	send_string 0, msg;
}

define_function init() {
	stack_var integer i;
	
	for (i = 1; i <= length_array(locationIds); i++) {
		setBookingTracker(i, locationIds[i], locationNames[i]);
	}
	
	set_length_array(bookings, length_array(locationIds));
}

define_function startPolling() {
	stack_var long pollTimes[1];
	
	pollTimes[1] = POLL_INTERVAL * 1000;
	
	if (!timeline_active(POLL_TL)) {
		timeline_create(POLL_TL,
				pollTImes, 
				1, 
				TIMELINE_RELATIVE, 
				TIMELINE_REPEAT);
		
		queryBookings();
	}
}

define_function stopPolling() {
	if (timeline_active(POLL_TL)) {
		timeline_kill(POLL_TL);
	}
}

define_function setBookingTracker(integer idx, long locationId, char locationName[]) {
	bookings[idx].location.id = type_cast(locationId);
	bookings[idx].location.name = locationName;
	// TODO we shouldn't have to pass in names but there doesn't seem to be a
	// way to query location info without there being an asset in there
}


define_function integer getLocationIdx(long locationId) {
	stack_var integer idx;
	
	log('updateActiveBooking() called');
	
	for (idx = 1; idx <= length_array(bookings); idx++) {
		if (bookings[idx].location.id == locationId) {
			return idx;
		}
	}
}

define_function updateActiveBooking(RmsEventBookingResponse booking) {
	stack_var integer idx;
	idx = getLocationIdx(booking.location);
	if (idx) {
		bookings[idx].activeBooking = booking;
		writeXml();
	}
}

define_function updateNextBooking(RmsEventBookingResponse booking) {
	stack_var integer idx;
	
	log('updateNextBooking() called');
	
	idx = getLocationIdx(booking.location);
	if (idx) {
		bookings[idx].nextBooking = booking;
		writeXml();
	}
}

define_function queryBookings() {
	stack_var integer i;
	
	log('queryBookings() called');
	
	for (i = 1; i <= length_array(bookings); i++) {
		RmsBookingActiveRequest(bookings[i].location.id);
		RmsBookingNextActiveRequest(bookings[i].location.id);
	}
}

define_function char[2048] bookingToXmlElement(RmsLocation location, RmsEventBookingResponse booking) {
	return XmlBuildElement('booking', "
			XmlBuildElement('location', "
				XmlBuildElement('id', itoa(location.id)),
				XmlBuildElement('name', location.name)
			"),
			XmlBuildElement('isPrivate', RmsBooleanString(booking.isPrivateEvent)),
			XmlBuildElement('startDate', booking.startDate),
			XmlBuildElement('startTime', booking.startTime),
			XmlBuildElement('endDate', booking.endDate),
			XmlBuildElement('endTime', booking.endTime),
			XmlBuildElement('subject', booking.subject),
			XmlBuildElement('details', booking.details),
			XmlBuildElement('isAllDayEvent', RmsBooleanString(booking.isAllDayEvent)),
			XmlBuildElement('organizer', booking.organizer),
			XmlBuildElement('attendees', booking.attendees)
		");
}

define_function writeXml() {
	stack_var char buf[16384];
	stack_var slong fileHandle;
	stack_var integer i;
	
	log('writeXml() called');
	
	buf = XmlBuildHeader('1.0', 'UTF-8');

	// loop through each of our locations and...
	for (i = 1; i <= length_array(bookings); i++) {
		
		// add in active bookings
		if (bookings[i].activeBooking.bookingId) {
			buf = "buf, bookingToXmlElement(bookings[i].location, bookings[i].activeBooking)";
		}
		
		// as well as thouse starting in the next 10 minutes
		if (bookings[i].nextBooking.bookingId <> '' &&
				bookings[i].nextBooking.minutesUntilStart <= 10) {
			buf = "buf, bookingToXmlElement(bookings[i].location, bookings[i].nextBooking)";
		}
	}
	
	fileHandle = file_open(filename, FILE_RW_NEW);
	
	file_write(fileHandle, buf, length_string(buf));
	
	file_close(fileHandle);
}

// RMS callbacks

define_function RmsEventClientOnline() {
	log('RmsEventClientOnline() called');
	startPolling();
}

define_function RmsEventClientOffline() {
	log('RmsEventClientOffline() called');
	stopPolling();
}

define_function RmsEventSchedulingActiveResponse(char isDefaultLocation,
		integer recordIndex,
		integer recordCount,
		char bookingId[],
		RmsEventBookingResponse eventBookingResponse) {
	log('RmsEventSchedulingActiveResponse() called');
	updateActiveBooking(eventBookingResponse);
}

define_function RmsEventSchedulingNextActiveResponse(CHAR isDefaultLocation,
		integer recordIndex,
		integer recordCount,
		char bookingId[],
		RmsEventBookingResponse eventBookingResponse) {
	log('RmsEventSchedulingNextActiveResponse() called');
	updateNextBooking(eventBookingResponse);
}

define_function RmsEventSchedulingActiveUpdated(CHAR bookingId[],
		RmsEventBookingResponse eventBookingResponse) {
	log('RmsEventSchedulingActiveUpdated() called');
	updateActiveBooking(eventBookingResponse);
}

define_function RmsEventSchedulingNextActiveUpdated(CHAR bookingId[],
		RmsEventBookingResponse eventBookingResponse) {
	log('RmsEventSchedulingNextActiveUpdated() called');
	updateNextBooking(eventBookingResponse);
}


define_start

init();


define_event

timeline_event[POLL_TL] {
	queryBookings();
}
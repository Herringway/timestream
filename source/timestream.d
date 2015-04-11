private import std.stdio;
private import std.datetime : TimeZone, SysTime, DateTime, TimeOfDay, days, msecs, Date, UTC;
private import core.time;
@safe:
enum DayRoll : bool { No, Yes };
/**
 * Represents a constantly-increasing time and date. Designed for usage in
 * scenarios where a full date and time are wanted, but may not be available at
 * the same times. Also allows for easy chronological sorting of data.
 * Bugs: Handles DST in older dates incorrectly, no leap second support
 */
struct TimeStreamer {
	public  immutable(TimeZone) timezone;
	public  DateTime datetime;
	private Duration _delta;
	private FracSec fraction;
	private bool timeJustSet = false;
	private bool _dayRolled = false;
	private bool adjustAmbiguity = false;
	/**
	 * Skips ahead to the specified time of day.
	 * Params: 
	 *			roll = Specifies whether the date should roll over automatically
	 * 			newTime = The time of day to skip to
	 */
	void set(DayRoll roll = DayRoll.Yes)(TimeOfDay newTime) {
		auto old = now;
		set(DateTime(datetime.date, newTime));
		if ((roll == DayRoll.Yes) && (old > now)) {
			set(DateTime(datetime.date+1.days, newTime));
			_delta = now - old;
			_dayRolled = true;
		}
	}
	/**
	 * Skips ahead to the specified date.
	 * Params: 
	 * 			newDate = The date to skip to
	 */
	void set(Date newDate) nothrow {
		set(DateTime(newDate, datetime.timeOfDay));
	}
	/**
	 * Skips ahead to the specified time.
	 * Params: 
	 * 			newTime = The time to skip to
	 */
	void set(DateTime newTime) nothrow {
		if (newTime.isAmbiguous(timezone) && (newTime < datetime + (adjustAmbiguity ? 1.hours : 0.hours)))
			adjustAmbiguity = true;
		else
			adjustAmbiguity = false;
		_delta = newTime - datetime;
		if (newTime == datetime)
			return;
		fraction = FracSec.zero;
		datetime = newTime;
		timeJustSet = true;
		_dayRolled = false;
	}
	alias add = opOpAssign!"+";
	void opOpAssign(string op)(Duration dur) if (op == "+") {
		datetime += dur;
		if (dur.total!"hnsecs" != 0)
			fraction = FracSec.from!"hnsecs"(dur.total!"hnsecs" + fraction.hnsecs);
		_delta += dur;
	}
	void opUnary(string s)() if (s == "++") {
		fraction = FracSec.from!"hnsecs"(fraction.hnsecs + 1);
		_delta = 1.hnsecs;
    }
	/**
	 * Time difference between "now" and the last set time.
	 * Returns: A Duration representing the time difference.
	 */
	deprecated("use delta instead") alias Delta = delta;
	@property auto delta() nothrow pure {
		return _delta + (adjustAmbiguity ? 1.hours : 0.hours);
	}
	/**
	 * Whether or not the date rolled ahead automatically.
	 */
	@property bool dayRolled() nothrow pure {
		return _dayRolled;
	}
	/**
	 * Returns: the current time represented by this stream in UTC.
	 */
	@property SysTime now() {
		return SysTime(datetime, fraction, timezone).fixDSTDifference().toUTC() + (adjustAmbiguity ? 1.hours : 0.hours);
	}
	/**
	 * Returns: Whether or not DST is in effect for the timezone at this time
	 */
 	@property bool DST() {
 		return SysTime(datetime, fraction, timezone).isDST2();
 	}
	/**
	 * Like now, except the smallest possible unit of time will be added to 
	 * ensure the time is in the "future," unless the time was just set.
	 * Returns: the "next" time in UTC. 
	 */
	@property SysTime next() {
		if (timeJustSet)
			timeJustSet = false;
		else
			++this;
		_dayRolled = false;
		return now();
	}
}

@trusted unittest {
	import std.datetime, std.exception;
	version(Windows) {
		auto timezone = WindowsTimeZone.getTimeZone("Pacific Standard Time");
	} else {
		auto timezone = TimeZone.getTimeZone("America/Los_Angeles");
	}
	auto stream = TimeStreamer(timezone);
	@trusted void test(T,U)(ref TimeStreamer stream, Duration delta, T a, U b) {
		stream.set(a);
		assert(stream.delta == delta, "Delta mismatch: "~delta.toString~" != "~stream.delta.toString());
		auto value = stream.next;
		static if (is(U == SysTime))
			assert(value == b, "Error: "~value.toString()~" != "~b.toUTC().toString());
		else
			assert(value == SysTime(b, UTC()), "Error: "~value.toString()~" != "~SysTime(b, UTC()).toString());
	}

	stream.set(DateTime(2005, 4, 2, 0, 0, 0));
	if (SysTime(DateTime(2005, 4, 2, 0, 0, 0), timezone).dstInEffect) {
		stderr.writeln("2005's DST time incorrect on this system, skipping 2005 DST tests");
	} else {
		test(stream, 29.days + 12.hours + 10.minutes, DateTime(2005, 1, 30, 12, 10, 0), DateTime(2005, 1, 30, 20, 10, 0));
		test(stream, 8.weeks + 6.days + 12.hours + 4.minutes, DateTime(2005, 4, 3, 0, 14, 0), DateTime(2005, 4, 3, 08, 14, 0));
		test(stream, 1.hours, DateTime(2005, 4, 3, 1, 14, 0), DateTime(2005, 4, 3, 09, 14, 0));
		assert(!stream.DST);
		assertThrown(stream.set(DateTime(2005, 4, 3, 2, 14, 0))); //This time does not exist
		test(stream, 1.hours, DateTime(2005, 4, 3, 3, 14, 0), DateTime(2005, 4, 3, 10, 14, 0));
		assert(stream.DST);
		test(stream, 1.hours, DateTime(2005, 4, 3, 4, 14, 0), DateTime(2005, 4, 3, 11, 14, 0));
		test(stream, 29.weeks + 6.days + 14.hours, DateTime(2005, 10, 30, 1, 14, 0), DateTime(2005, 10, 30, 8, 14, 0));
		test(stream, 59.minutes, DateTime(2005, 10, 30, 1, 13, 0), DateTime(2005, 10, 30, 9, 13, 0));
		test(stream, 1.hours + 1.minutes, DateTime(2005, 10, 30, 2, 14, 0), DateTime(2005, 10, 30, 10, 14, 0));
		test(stream, -1 * (29.weeks + 4.days + 10.hours), DateTime(2005, 4, 6, 0, 14, 0), DateTime(2005, 4, 6, 7, 14, 0));
	}
	stream.set(DateTime(2005,1,1,0,0,0));

	test(stream, 12.hours + 14.minutes, TimeOfDay(12, 14, 0), DateTime(2005, 1, 1, 20, 14, 0));
	test(stream, 23.hours, TimeOfDay(11, 14, 0), DateTime(2005, 1, 2, 19, 14, 0));
	test(stream, 1.hours, TimeOfDay(12, 14, 0), DateTime(2005, 1, 2, 20, 14, 0));
	test(stream, 0.hours, TimeOfDay(12, 14, 0), SysTime(DateTime(2005, 1, 2, 20, 14, 0), FracSec.from!"hnsecs"(1), UTC()));

	if (DateTime(2015, 06, 30, 17, 59, 60).ifThrown(DateTime.init) != DateTime.init)
		test(stream, 547.weeks + 2.days + 4.hours + 45.minutes + 59.seconds + 999.msecs + 999.usecs + 9.hnsecs, DateTime(2015, 06, 30, 17, 59, 60), DateTime(2015, 06, 30, 23, 59, 60));
	else
		writeln("Leap seconds unsupported, skipping");
	
	auto t1 = stream.next;
	stream += 1.msecs;
	auto t2 = stream.next;
	assert(t1 < t2);
	assert(stream.next < stream.next);
	assert(stream.delta == 1.hnsecs);
	stream.set(DateTime(2015, 03, 15, 3, 0, 0));
	stream.set(TimeOfDay(4,0,0));
	assert(stream.delta == 1.hours);

	stream.set!(DayRoll.Yes)(TimeOfDay(3,0,0));
	assert(stream.delta == 23.hours);
	assert(stream.dayRolled);
	stream.set!(DayRoll.No)(TimeOfDay(2,0,0));
	assert(stream.delta == -1.hours);
	assert(!stream.dayRolled);

	stream.set(DateTime(2015, 11,  1, 1, 30, 0));
	stream.set(DateTime(2015, 11,  1, 1, 0, 0));
	writeln(stream.now);
	assert(stream.now == SysTime(DateTime(2015, 11,  1, 9, 0, 0), UTC()));
	assert(stream.delta == 30.minutes);
	assert(!stream.dayRolled);
	stream.set(DateTime(2015, 11,  1, 2, 0, 0));
	assert(stream.now == SysTime(DateTime(2015, 11,  1, 10, 0, 0), UTC()));
	assert(stream.delta == 1.hours);
	stream.set(DateTime(2002, 10,  27, 1, 0, 0));
	stream.set(TimeOfDay(1, 0, 0));
	assert(!stream.dayRolled);
	stream.set(TimeOfDay(1, 53, 0));
	stream.set(TimeOfDay(2,  0, 0));
	assert(!stream.dayRolled);
}
enum DSTStartDates = [Date(2015, 03, 8), Date(2014, 03, 9), Date(2013, 03, 10), Date(2012, 03, 11), Date(2011, 03, 13), Date(2010, 03,  14), Date(2009, 03,  8), Date(2008, 03,  9), Date(2007, 03, 11), Date(2006, 04, 02), Date(2005, 04, 03), Date(2004, 04, 04), Date(2003, 04, 06), Date(2002, 04, 07), Date(2001, 04, 01)];
enum DSTEndDates   = [Date(2015, 11, 1), Date(2014, 11, 2), Date(2013, 11, 03), Date(2012, 11, 04), Date(2011, 11, 06), Date(2010, 11,  07), Date(2009, 11,  1), Date(2008, 11,  2), Date(2007, 11,  4), Date(2006, 10, 29), Date(2005, 10, 30), Date(2004, 10, 31), Date(2003, 10, 26), Date(2002, 10, 27), Date(2001, 10, 28)];
bool isDST2(SysTime systime) {
	return (cast(DateTime)systime).isDST2(systime.timezone);
}
bool isDST2(DateTime datetime, immutable(TimeZone) tz) {
	import std.algorithm : countUntil;
	if (!tz.hasDST)
		return false;
	auto found = DSTStartDates.countUntil!"a <= b.date"(datetime);
	if (found == -1)
		return false;
	if (DateTime(DSTStartDates[found], TimeOfDay(3, 0, 0)) > datetime)
		return false;
	if (DateTime(DSTEndDates[found], TimeOfDay(2, 0, 0)) <= datetime)
		return false;
	return true;
}
unittest {
	import std.datetime;
	version(Windows) {
		auto timezone = WindowsTimeZone.getTimeZone("Pacific Standard Time");
	} else {
		auto timezone = TimeZone.getTimeZone("America/Los_Angeles");
	}
	assert(DateTime(2015, 03,  8, 3, 0, 0).isDST2(timezone));
	assert(!DateTime(2015, 03,  8, 1, 0, 0).isDST2(timezone));
	assert(DateTime(2015, 11,  1, 1, 0, 0).isDST2(timezone));
	assert(!DateTime(2015, 11,  1, 2, 0, 0).isDST2(timezone));
}
SysTime fixDSTDifference(SysTime input) {
	if (input.isAmbiguous)
		return input;
	if (input.dstInEffect && !input.isDST2)
		return input + 1.hours;
	else if (!input.dstInEffect && input.isDST2)
		return input - 1.hours;
	return input;
}
@trusted unittest {
	import std.datetime;
	version(Windows) {
		auto timezone = WindowsTimeZone.getTimeZone("Pacific Standard Time");
	} else {
		auto timezone = TimeZone.getTimeZone("America/Los_Angeles");
	}
	assert(SysTime(DateTime(2002, 10, 27, 1, 53, 0), timezone).fixDSTDifference() == SysTime(DateTime(2002, 10, 27, 1, 53, 0), timezone));
	assert(SysTime(DateTime(2002, 10, 27, 2, 0, 0), timezone).fixDSTDifference().toUTC() == SysTime(DateTime(2002, 10, 27, 10, 0, 0), UTC()));
	assert(SysTime(DateTime(2002, 12, 27, 2, 0, 0), timezone).fixDSTDifference().toUTC() == SysTime(DateTime(2002, 12, 27, 10, 0, 0), UTC()));

}
bool isAmbiguous(SysTime systime) @safe nothrow {
	return (cast(DateTime)systime).isAmbiguous(systime.timezone);
}
bool isAmbiguous(DateTime datetime, immutable(TimeZone) timezone) @safe nothrow {
	import std.algorithm : canFind;
	if (!timezone.hasDST)
		return false;
	scope(failure) return false;
	if ((datetime.timeOfDay < TimeOfDay(1,0,0)) || (datetime.timeOfDay >= TimeOfDay(2,0,0)))
		return false;
	if (!DSTEndDates.canFind(datetime.date))
		return false;
	return true;
}
SysTime SysTime2(DateTime datetime, immutable(TimeZone) tz) in {
	assert(datetime.isAmbiguous(tz), "Time is not ambiguous");
} body {
	return SysTime(datetime, tz)+1.hours;
}

unittest {
	import std.datetime;
	version(Windows) {
		auto timezone = WindowsTimeZone.getTimeZone("Pacific Standard Time");
	} else {
		auto timezone = TimeZone.getTimeZone("America/Los_Angeles");
	}
	assert(DateTime(2015, 11,  1, 1, 0, 0).isAmbiguous(timezone));
	assert(SysTime2(DateTime(2015, 11,  1, 1, 0, 0), timezone) == SysTime(DateTime(2015, 11,  1, 9, 0, 0), UTC()));
	assert(DateTime(2014, 11,  2, 1, 0, 0).isAmbiguous(timezone));
	assert(SysTime2(DateTime(2014, 11,  2, 1, 0, 0), timezone) == SysTime(DateTime(2014, 11,  2, 9, 0, 0), UTC()));
	assert(DateTime(2013, 11,  3, 1, 0, 0).isAmbiguous(timezone));
	assert(SysTime2(DateTime(2013, 11,  3, 1, 0, 0), timezone) == SysTime(DateTime(2013, 11,  3, 9, 0, 0), UTC()));
	assert(DateTime(2012, 11,  4, 1, 0, 0).isAmbiguous(timezone));
	assert(SysTime2(DateTime(2012, 11,  4, 1, 0, 0), timezone) == SysTime(DateTime(2012, 11,  4, 9, 0, 0), UTC()));
	assert(DateTime(2011, 11,  6, 1, 0, 0).isAmbiguous(timezone));
	assert(SysTime2(DateTime(2011, 11,  6, 1, 0, 0), timezone) == SysTime(DateTime(2011, 11,  6, 9, 0, 0), UTC()));
	assert(DateTime(2010, 11,  7, 1, 0, 0).isAmbiguous(timezone));
	assert(SysTime2(DateTime(2010, 11,  7, 1, 0, 0), timezone) == SysTime(DateTime(2010, 11,  7, 9, 0, 0), UTC()));
	assert(DateTime(2009, 11,  1, 1, 0, 0).isAmbiguous(timezone));
	assert(SysTime2(DateTime(2009, 11,  1, 1, 0, 0), timezone) == SysTime(DateTime(2009, 11,  1, 9, 0, 0), UTC()));
	assert(DateTime(2008, 11,  2, 1, 0, 0).isAmbiguous(timezone));
	assert(SysTime2(DateTime(2008, 11,  2, 1, 0, 0), timezone) == SysTime(DateTime(2008, 11,  2, 9, 0, 0), UTC()));
	assert(DateTime(2007, 11,  4, 1, 0, 0).isAmbiguous(timezone));
	assert(SysTime2(DateTime(2007, 11,  4, 1, 0, 0), timezone) == SysTime(DateTime(2007, 11,  4, 9, 0, 0), UTC()));
	assert(DateTime(2006, 10, 29, 1, 0, 0).isAmbiguous(timezone));
	assert(SysTime2(DateTime(2006, 10, 29, 1, 0, 0), timezone) == SysTime(DateTime(2006, 10, 29, 9, 0, 0), UTC()));
	assert(DateTime(2005, 10, 30, 1, 0, 0).isAmbiguous(timezone));
	assert(SysTime2(DateTime(2005, 10, 30, 1, 0, 0), timezone) == SysTime(DateTime(2005, 10, 30, 9, 0, 0), UTC()));
	assert(DateTime(2004, 10, 31, 1, 0, 0).isAmbiguous(timezone));
	assert(SysTime2(DateTime(2004, 10, 31, 1, 0, 0), timezone) == SysTime(DateTime(2004, 10, 31, 9, 0, 0), UTC()));
	assert(DateTime(2003, 10, 26, 1, 0, 0).isAmbiguous(timezone));
	assert(SysTime2(DateTime(2003, 10, 26, 1, 0, 0), timezone) == SysTime(DateTime(2003, 10, 26, 9, 0, 0), UTC()));
	assert(DateTime(2002, 10, 27, 1, 0, 0).isAmbiguous(timezone));
	assert(SysTime2(DateTime(2002, 10, 27, 1, 0, 0), timezone) == SysTime(DateTime(2002, 10, 27, 9, 0, 0), UTC()));
	assert(DateTime(2001, 10, 28, 1, 0, 0).isAmbiguous(timezone));
	assert(SysTime2(DateTime(2001, 10, 28, 1, 0, 0), timezone) == SysTime(DateTime(2001, 10, 28, 9, 0, 0), UTC()));
}
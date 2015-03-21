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
	immutable(TimeZone) timezone;
	private DateTime datetime;
	private Duration _delta;
	private FracSec fraction;
	private bool timeJustSet = false;
	private bool _dayRolled = false;
	/**
	 * Skips ahead to the specified time of day.
	 * Params: 
	 *			roll = Specifies whether the date should roll over automatically
	 * 			newTime = The time of day to skip to
	 */
	void set(DayRoll roll = DayRoll.Yes)(TimeOfDay newTime) nothrow pure {
		if ((roll == DayRoll.Yes) && (newTime - datetime.timeOfDay < 0.hnsecs)) {
			set(DateTime(datetime.date+1.days, newTime));
			_dayRolled = true;
		}
		else {
			set(DateTime(datetime.date, newTime));
		}
	}
	/**
	 * Skips ahead to the specified date.
	 * Params: 
	 * 			newDate = The date to skip to
	 */
	void set(Date newDate) nothrow pure {
		set(DateTime(newDate, datetime.timeOfDay));
	}
	/**
	 * Skips ahead to the specified time.
	 * Params: 
	 * 			newTime = The time to skip to
	 */
	void set(DateTime newTime) nothrow pure {
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
		return _delta;
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
		return SysTime(datetime, fraction, timezone).toUTC();
	}
	/**
	 * Returns: Whether or not DST is in effect for the timezone at this time
	 */
 	@property bool DST() {
 		return SysTime(datetime, fraction, timezone).dstInEffect();
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
}
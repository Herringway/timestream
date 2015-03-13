private import std.stdio;
private import std.datetime : TimeZone, SysTime, DateTime, TimeOfDay, days, msecs, Date, UTC;
private import core.time;
@safe:
enum AutoRoll : bool { No, Yes };
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
	private Duration delta;
	private FracSec fraction;
	private bool onlyTimeAssigned = false;
	/**
	 * Skips ahead to the specified time of day.
	 * Params: 
	 *			roll = Specifies whether the date should roll over automatically
	 * 			newTime = The time of day to skip to
	 */
	void set(DayRoll roll = DayRoll.Yes)(TimeOfDay newTime) nothrow pure {
		set(DateTime(datetime.date, newTime));
		if (roll == DayRoll.Yes)
			onlyTimeAssigned = true;
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
		if (newTime != datetime)
			fraction = FracSec.zero;
		delta = newTime - datetime;
		datetime = newTime;
		onlyTimeAssigned = false;
	}
	alias add = opOpAssign!"+";
	void opOpAssign(string op)(Duration dur) if (op == "+") {
		datetime += dur;
		delta += dur;
		fraction = FracSec.from!"hnsecs"(dur.total!"hnsecs" + fraction.hnsecs);
	}
	/**
	 * Time difference between "now" and the last set time.
	 * Returns: A Duration representing the time difference.
	 */
	auto Delta() nothrow pure {
		return delta;
	}
	/**
	 * Returns the "next" time. If rolling is enabled, the smallest possible 
	 * unit of time will be added to the time to ensure the next time is in the
	 * future.
	 * Params: 
	 *			roll = Specifies whether the time should automatically increment
	 */
	SysTime next(AutoRoll roll = AutoRoll.Yes)() {
		if (onlyTimeAssigned && (delta < 0.seconds))
			datetime += 1.days;
		auto output = SysTime(datetime, fraction, timezone).toUTC();
		if (roll == AutoRoll.Yes)
			fraction = FracSec.from!"hnsecs"(fraction.hnsecs + 1);
		return output;
	}
}

unittest {
	import std.datetime, std.exception;
	version(Windows) {
		auto stream = TimeStreamer(WindowsTimeZone.getTimeZone("Pacific Standard Time"));
	} else {
		auto stream = TimeStreamer(TimeZone.getTimeZone("America/Los_Angeles"));
	}

	stream.set(DateTime(2005,1,1,0,0,0));
	void test(T)(ref TimeStreamer stream, T a, DateTime b, FracSec f = FracSec.zero) {
		stream.set(a);
		auto value = stream.next();
		assert(value == SysTime(b, f, UTC()), "Error: "~value.toString()~" != "~SysTime(b, f, UTC()).toString());
	}

	//DST shenanigans prevent the following tests from working correctly at the moment...
	//Upstream may be the correct place to deal with this
	
	/+test(stream, DateTime(2005, 1, 30, 12, 10, 0), DateTime(2005, 01, 30, 20, 10, 0));
	test(stream, DateTime(2005, 4, 3, 0, 14, 0), DateTime(2005, 10, 30, 08, 14, 0));
	test(stream, DateTime(2005, 4, 3, 1, 14, 0), DateTime(2005, 10, 30, 09, 14, 0));
	stream.set(DateTime(2005, 4, 3, 2, 14, 0));
	assertThrown(stream.next());
	test(stream, DateTime(2005, 4, 3, 3, 14, 0), DateTime(2005, 10, 30, 10, 14, 0));
	test(stream, DateTime(2005, 4, 3, 4, 14, 0), DateTime(2005, 10, 30, 11, 14, 0));
	test(stream, DateTime(2005, 10, 30, 1, 14, 0), DateTime(2005, 10, 30, 08, 14, 0));
	test(stream, DateTime(2005, 10, 30, 1, 13, 0), DateTime(2005, 10, 30, 09, 13, 0));
	test(stream, DateTime(2005, 10, 30, 2, 14, 0), DateTime(2005, 10, 30, 10, 14, 0));
	test(stream, DateTime(2005, 4, 6, 0, 14, 0), DateTime(2005, 04, 06, 07, 14, 0));+/

	test(stream, TimeOfDay(12, 14, 0), DateTime(2005, 1, 1, 20, 14, 0));
	test(stream, TimeOfDay(11, 14, 0), DateTime(2005, 1, 2, 19, 14, 0));
	test(stream, TimeOfDay(12, 14, 0), DateTime(2005, 1, 2, 20, 14, 0));
	test(stream, TimeOfDay(12, 14, 0), DateTime(2005, 1, 2, 20, 14, 0), FracSec.from!"hnsecs"(1));

	//Leap seconds unsupported
	//test(stream, DateTime(2015, 06, 30, 17, 59, 60), DateTime(2015, 06, 30, 23, 59, 60));
	
	stream.set(TimeOfDay(12, 14, 0));
	auto t1 = stream.next();
	stream += 1.msecs;
	auto t2 = stream.next();
	assert(t1 < t2);
	assert(stream.next!(AutoRoll.Yes)() < stream.next!(AutoRoll.Yes)());
}
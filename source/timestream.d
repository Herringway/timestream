module timestream;
private import std.stdio;
private import std.datetime : TimeZone, SysTime, DateTime, TimeOfDay, days, msecs, Date, UTC;
private import std.typecons : Flag;
private import core.time;
@safe:
alias DayRoll = Flag!"DayRoll";
/**
 * Represents a constantly-increasing time and date. Designed for usage in
 * scenarios where a full date and time are wanted, but may not be available at
 * the same times. Also allows for easy chronological sorting of data. All
 * operations are done in UTC.
 * Bugs: No leap second support
 */
struct TimeStreamer {
	public  DateTime datetime;
	private Duration _delta;
	private Duration fraction;
	private bool timeJustSet = false;
	private bool _dayRolled = false;
	/**
	 * Skips ahead to the specified time of day. If DayRoll.yes is specified
	 * (the default), then the day will automatically increment when the time
	 * is less than the last given time.
	 * Params:
	 *			roll = Specifies whether the date should roll over automatically
	 * 			newTime = The time of day to skip to
	 */
	void set(DayRoll roll = DayRoll.yes)(TimeOfDay newTime) {
		const old = now;
		set(DateTime(datetime.date, newTime));
		if ((roll == DayRoll.yes) && (old > now)) {
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
	void set(DateTime newTime) nothrow pure {
		_delta = newTime - datetime;
		if (newTime == datetime)
			return;
		fraction = 0.hnsecs;
		datetime = newTime;
		timeJustSet = true;
		_dayRolled = false;
	}
	alias add = opOpAssign!"+";
	void opOpAssign(string op)(Duration dur) nothrow pure if (op == "+") {
		datetime += dur;
		if (dur.total!"hnsecs" != 0)
			fraction += dur.total!"hnsecs".hnsecs;
		_delta += dur;
	}
	void opUnary(string s)() @nogc nothrow pure if (s == "++") {
		fraction += 1.hnsecs;
		_delta = 1.hnsecs;
    }
	/**
	 * Time difference between "now" and the last set time.
	 * Returns: A Duration representing the time difference.
	 */
	@property auto delta() nothrow pure @nogc {
		return _delta;
	}
	/**
	 * Whether or not the date rolled ahead automatically.
	 */
	@property bool dayRolled() nothrow pure @nogc {
		return _dayRolled;
	}
	/**
	 * Returns: the current time represented by this stream in UTC.
	 */
	@property SysTime now() {
		return SysTime(datetime, fraction, UTC());
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

unittest {
	import std.exception : ifThrown;
	auto stream = TimeStreamer();
	void test(T)(ref TimeStreamer stream, Duration delta, T a) {
		import std.conv : to;
		stream.set(a);
		assert(stream.delta == delta, "Delta mismatch: "~delta.toString~" != "~stream.delta.toString());
		assert(stream.now.to!T == a);
		assert(stream.next.to!T == a);
	}

	stream.set(DateTime(2005, 4, 2, 0, 0, 0));
	test(stream, -8.weeks - 5.days - 11.hours - 50.minutes, DateTime(2005, 1, 30, 12, 10, 0));
	test(stream, 8.weeks + 6.days + 12.hours + 4.minutes, DateTime(2005, 4, 3, 0, 14, 0));
	test(stream, 1.hours, DateTime(2005, 4, 3, 1, 14, 0));
	test(stream, 2.hours, DateTime(2005, 4, 3, 3, 14, 0));
	test(stream, 1.hours, DateTime(2005, 4, 3, 4, 14, 0));
	test(stream, 29.weeks + 6.days + 21.hours, DateTime(2005, 10, 30, 1, 14, 0));
	test(stream, -1.minutes, DateTime(2005, 10, 30, 1, 13, 0));
	test(stream, 1.hours + 1.minutes, DateTime(2005, 10, 30, 2, 14, 0));
	test(stream, -1 * (29.weeks + 4.days + 2.hours), DateTime(2005, 4, 6, 0, 14, 0));
	stream.set(DateTime(2005,1,1,0,0,0));

	test(stream, 12.hours + 14.minutes, TimeOfDay(12, 14, 0));
	test(stream, 23.hours, TimeOfDay(11, 14, 0));
	test(stream, 1.hours, TimeOfDay(12, 14, 0));
	test(stream, 0.hours, TimeOfDay(12, 14, 0));

	static if (DateTime(2015, 06, 30, 17, 59, 60).ifThrown(DateTime.init) != DateTime.init)
		test(stream, 547.weeks + 2.days + 4.hours + 45.minutes + 59.seconds + 999.msecs + 999.usecs + 9.hnsecs, DateTime(2015, 06, 30, 17, 59, 60));
	else
		pragma(msg, "Leap seconds unsupported, skipping test");

	const t1 = stream.next;
	stream += 1.msecs;
	assert(t1 < stream.next);
	assert(stream.next < stream.next);
	assert(stream.delta == 1.hnsecs);
	stream.set(DateTime(2015, 03, 15, 3, 0, 0));
	stream.set(TimeOfDay(4,0,0));
	assert(stream.delta == 1.hours);

	stream.set!(DayRoll.yes)(TimeOfDay(3,0,0));
	assert(stream.delta == 23.hours);
	assert(stream.dayRolled);
	stream.set!(DayRoll.no)(TimeOfDay(2,0,0));
	assert(stream.delta == -1.hours);
	assert(!stream.dayRolled);

	stream.set(DateTime(2015, 11,  1, 1, 30, 0));
	stream.set(DateTime(2015, 11,  1, 1, 0, 0));
	assert(stream.delta == -30.minutes);
	assert(!stream.dayRolled);
	stream.set(DateTime(2015, 11,  1, 2, 0, 0));
	assert(stream.delta == 1.hours);
	stream.set(DateTime(2002, 10,  27, 1, 0, 0));
	stream.set(TimeOfDay(1, 0, 0));
	assert(!stream.dayRolled);
	stream.set(TimeOfDay(1, 53, 0));
	stream.set(TimeOfDay(2,  0, 0));
	assert(!stream.dayRolled);
	stream.set(Date(2002, 10, 28));
	assert(!stream.dayRolled);
}
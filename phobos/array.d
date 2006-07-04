
module phobos.array;

private import phobos.c.stdio;

class ArrayBoundsError : Exception
{
  private:

    uint linnum;
    char[] filename;

  public:
    this(char[] filename, uint linnum)
    {
	this.linnum = linnum;
	this.filename = filename;

	char[] buffer = new char[19 + filename.length + linnum.sizeof * 3 + 1];
	int len;
	len = sprintf(buffer, "ArrayBoundsError %.*s(%u)", filename, linnum);
	super(buffer[0..len]);
    }
}


/********************************************
 * Called by the compiler generated module assert function.
 * Builds an ArrayBoundsError exception and throws it.
 */

extern (C) static void _d_array_bounds(char[] filename, uint line)
{
    //printf("_d_assert(%s, %d)\n", (char *)filename, line);
    ArrayBoundsError a = new ArrayBoundsError(filename, line);
    //printf("assertion %p created\n", a);
    throw a;
}

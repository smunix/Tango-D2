/*******************************************************************************

        copyright:      Copyright (c) 2008 Kris Bell. All rights reserved

        license:        BSD style: $(LICENSE)

        version:        Apr 2008: Initial release

        authors:        Kris

        Based upon Doug Lea's Java collection package

*******************************************************************************/

module tango.util.container.HashSet;

private import  tango.util.container.Slink;

public  import  tango.util.container.Container;

private import tango.util.container.model.IContainer;

/*******************************************************************************

        Hash table implementation of a Set

        ---
        Iterator iterator ()
        int opApply (int delegate(ref V value) dg)

        bool add (V element)
        bool contains (V element)
        bool take (ref V element)
        bool remove (V element)
        uint remove (IContainer!(V) e)
        bool replace (V oldElement, V newElement)

        uint size ()
        bool isEmpty ()
        V[] toArray (V[] dst)
        HashSet dup ()
        HashSet clear ()
        HashSet reset ()

        uint buckets ()
        void buckets (uint cap)
        float threshold ()
        void threshold (float desired)
        ---

*******************************************************************************/

class HashSet (V, alias Hash = Container.hash, 
                  alias Reap = Container.reap, 
                  alias Heap = Container.Collect) 
                  : IContainer!(V)
{
        // use this type for Allocator configuration
        public alias Slink!(V)  Type;
        
        private alias Type      *Ref;

        private alias Heap!(Type) Alloc;

        // Each table entry is a list - null if no table allocated
        private Ref             table[];
        
        // number of elements contained
        private uint            count;

        // the threshold load factor
        private float           loadFactor;

        // configured heap manager
        private Alloc           heap;
        
        // mutation tag updates on each change
        private uint            mutation;

        /***********************************************************************

                Construct a HashSet instance

        ***********************************************************************/

        this (float f = Container.defaultLoadFactor)
        {
                loadFactor = f;
        }

        /***********************************************************************

                Clean up when deleted

        ***********************************************************************/

        ~this ()
        {
                reset;
        }

        /***********************************************************************

                Return the configured allocator
                
        ***********************************************************************/

        final Alloc allocator ()
        {
                return heap;
        }

        /***********************************************************************

                Return a generic iterator for contained elements
                
        ***********************************************************************/

        final Iterator iterator ()
        {
                Iterator i = void;
                i.mutation = mutation;
                i.table = table;
                i.owner = this;
                i.cell = null;
                i.row = 0;
                return i;
        }

        /***********************************************************************


        ***********************************************************************/

        final int opApply (int delegate(ref V value) dg)
        {
                auto freach = iterator.freach;
                return freach.opApply (dg);
        }

        /***********************************************************************

                Return the number of elements contained
                
        ***********************************************************************/

        final uint size ()
        {
                return count;
        }
        
        /***********************************************************************

                Add a new element to the set. Does not add if there is an
                equivalent already present. Returns true where an element
                is added, false where it already exists
                
                Time complexity: O(1) average; O(n) worst.
                
        ***********************************************************************/

        final bool add (V element)
        {
                if (table is null)
                    resize (Container.defaultInitialBuckets);

                auto h = Hash  (element, table.length);
                auto hd = table[h];

                if (hd && hd.find (element))
                    return false;

                table[h] = allocate.set (element, hd);
                increment;

                // only check if bin was nonempty                    
                if (hd)
                    checkLoad; 
                return true;
        }

        /***********************************************************************

                Does this set contain the given element?
        
                Time complexity: O(1) average; O(n) worst
                
        ***********************************************************************/

        final bool contains (V element)
        {
                if (count)
                   {
                   auto p = table[Hash (element, table.length)];
                   if (p && p.find (element))
                       return true;
                   }
                return false;
        }

        /***********************************************************************

                Make an independent copy of the container. Does not clone
                elements
                
                Time complexity: O(n)
                
        ***********************************************************************/

        final HashSet dup ()
        {
                auto clone = new HashSet!(V, Hash, Reap, Heap) (loadFactor);
                
                if (count)
                   {
                   clone.buckets (buckets);

                   foreach (value; iterator.freach)
                            clone.add (value);
                   }
                return clone;
        }

        /***********************************************************************

                Remove the provided element. Returns true if found, false
                otherwise
                
                Time complexity: O(1) average; O(n) worst

        ***********************************************************************/

        final uint remove (V element, bool all)
        {
                return remove(element) ? 1 : 0;
        }

        /***********************************************************************

                Remove the provided element. Returns true if found, false
                otherwise
                
                Time complexity: O(1) average; O(n) worst

        ***********************************************************************/

        final bool remove (V element)
        {
                if (count)
                   {
                   auto h = Hash (element, table.length);
                   auto hd = table[h];
                   auto trail = hd;
                   auto p = hd;

                   while (p)
                         {
                         auto n = p.next;
                         if (element == p.value)
                            {
                            decrement (p);
                            if (p is table[h])
                               {
                               table[h] = n;
                               trail = n;
                               }
                            else
                               trail.next = n;
                            return true;
                            } 
                         else
                            {
                            trail = p;
                            p = n;
                            }
                         }
                   }
                return false;
        }

        /***********************************************************************

                Replace the first instance of oldElement with newElement.
                Returns true if oldElement was found and replaced, false
                otherwise.
                
        ***********************************************************************/

        final uint replace (V oldElement, V newElement, bool all)
        {
                return replace (oldElement, newElement) ? 1 : 0;
        }

        /***********************************************************************

                Replace the first instance of oldElement with newElement.
                Returns true if oldElement was found and replaced, false
                otherwise.
                
        ***********************************************************************/

        final bool replace (V oldElement, V newElement)
        {

                if (count && oldElement != newElement)
                   if (contains (oldElement))
                      {
                      remove (oldElement);
                      add (newElement);
                      return true;
                      }
                return false;
        }

        /***********************************************************************

                Remove and expose the first element. Returns false when no
                more elements are contained
        
                Time complexity: O(n)

        ***********************************************************************/

        final bool take (ref V element)
        {
                if (count)
                    foreach (ref list; table)
                             if (list)
                                {
                                auto p = list;
                                element = p.value;
                                list = p.next;
                                decrement (p);
                                return true;
                                }
                return false;
        }

        /***********************************************************************

        ************************************************************************/

        public void add (IContainer!(V) e)
        {
                foreach (value; e)
                         add (value);
        }

        /***********************************************************************

        ************************************************************************/

        public uint remove (IContainer!(V) e)
        {
                uint c;
                foreach (value; e)
                         if (remove (value))
                             ++c;
                return c;
        }

        /***********************************************************************

                Clears the HashMap contents. Various attributes are
                retained, such as the internal table itself. Invoke
                reset() to drop everything.

                Time complexity: O(n)
                
        ***********************************************************************/

        final HashSet clear ()
        {
                return clear (false);
        }

        /***********************************************************************

                Reset the HashSet contents and optionally configure a new
                heap manager. This releases more memory than clear() does

                Time complexity: O(1)
                
        ***********************************************************************/

        final HashSet reset ()
        {
                clear (true);
                heap.collect (table);
                table = null;
                return this;
        }

        /***********************************************************************

                Return the number of buckets

                Time complexity: O(1)

        ***********************************************************************/

        final uint buckets ()
        {
                return table ? table.length : 0;
        }

        /***********************************************************************

                Set the number of buckets and resize as required
                
                Time complexity: O(n)

        ***********************************************************************/

        final void buckets (uint cap)
        {
                if (cap < Container.defaultInitialBuckets)
                    cap = Container.defaultInitialBuckets;

                if (cap !is buckets)
                    resize (cap);
        }

        /***********************************************************************

                Return the resize threshold
                
                Time complexity: O(1)

        ***********************************************************************/

        final float threshold ()
        {
                return loadFactor;
        }

        /***********************************************************************

                Set the resize threshold, and resize as required
                
                Time complexity: O(n)
                
        ***********************************************************************/

        final void threshold (float desired)
        {
                assert (desired > 0.0);
                loadFactor = desired;
                if (table)
                    checkLoad;
        }

        /***********************************************************************

                Copy and return the contained set of values in an array, 
                using the optional dst as a recipient (which is resized 
                as necessary).

                Returns a slice of dst representing the container values.
                
                Time complexity: O(n)
                
        ***********************************************************************/

        final V[] toArray (V[] dst = null)
        {
                if (dst.length < count)
                    dst.length = count;

                int i = 0;
                foreach (v; this)
                         dst[i++] = v;
                return dst [0 .. count];                        
        }

        /***********************************************************************

                Is this container empty?
                
                Time complexity: O(1)
                
        ***********************************************************************/

        final bool isEmpty ()
        {
                return count is 0;
        }

        /***********************************************************************

                Sanity check
                 
        ***********************************************************************/

        final HashSet check()
        {
                assert(!(table is null && count !is 0));
                assert((table is null || table.length > 0));
                assert(loadFactor > 0.0f);

                if (table)
                   {
                   int c = 0;
                   for (int i = 0; i < table.length; ++i)
                       {
                       for (auto p = table[i]; p; p = p.next)
                           {
                           ++c;
                           assert(contains(p.value));
                           assert(Hash (p.value, table.length) is i);
                           }
                       }
                   assert(c is count);
                   }
                return this;
        }

        /***********************************************************************

                Allocate a node instance. This is used as the default allocator
                 
        ***********************************************************************/

        private Ref allocate ()
        {
                return heap.allocate;
        }
        
        /***********************************************************************

                 Check to see if we are past load factor threshold. If so,
                 resize so that we are at half of the desired threshold.
                 
        ***********************************************************************/

        private void checkLoad ()
        {
                float fc = count;
                float ft = table.length;
                if (fc / ft > loadFactor)
                    resize (2 * cast(int)(fc / loadFactor) + 1);
        }

        /***********************************************************************

                resize table to new capacity, rehashing all elements
                
        ***********************************************************************/

        private void resize (uint newCap)
        {
                //Stdout.formatln ("resize {}", newCap);
                auto newtab = heap.allocate (newCap);
                mutate;

                foreach (bucket; table)
                         while (bucket)
                               {
                               auto n = bucket.next;
                               auto h = Hash (bucket.value, newCap);
                               bucket.next = newtab[h];
                               newtab[h] = bucket;
                               bucket = n;
                               }

                // release the prior table and assign new one
                heap.collect (table);
                table = newtab;
        }

        /***********************************************************************

                Remove the indicated node. We need to traverse buckets
                for this, since we're singly-linked only. Better to save
                the per-node memory than to gain a little on each remove

                Used by iterators only
                 
        ***********************************************************************/

        private bool remove (Ref node, uint row)
        {
                auto hd = table[row];
                auto trail = hd;
                auto p = hd;

                while (p)
                      {
                      auto n = p.next;
                      if (p is node)
                         {
                         decrement (p);
                         if (p is hd)
                             table[row] = n;
                         else
                            trail.next = n;
                         return true;
                         } 
                      else
                         {
                         trail = p;
                         p = n;
                         }
                      }
                return false;
        }

        /***********************************************************************

                Clears the HashSet contents. Various attributes are
                retained, such as the internal table itself. Invoke
                reset() to drop everything.

                Time complexity: O(n)
                
        ***********************************************************************/

        private HashSet clear (bool all)
        {
                mutate;

                // collect each node if we can't collect all at once
                if (heap.collect(all) is false)
                    foreach (ref v; table)
                             while (v)
                                   {
                                   auto n = v.next;
                                   decrement (v);
                                   v = n;
                                   }

                // retain table, but remove bucket chains
                foreach (ref v; table)
                         v = null;

                count = 0;
                return this;
        }

        /***********************************************************************

                new element was added
                
        ***********************************************************************/

        private void increment()
        {
                ++mutation;
                ++count;
        }
        
        /***********************************************************************

                element was removed
                
        ***********************************************************************/

        private void decrement (Ref p)
        {
                Reap (p.value);
                heap.collect (p);
                ++mutation;
                --count;
        }
        
        /***********************************************************************

                set was changed
                
        ***********************************************************************/

        private void mutate()
        {
                ++mutation;
        }

        /***********************************************************************

                foreach support for iterators
                
        ***********************************************************************/

        private struct Freach
        {
                bool delegate(ref V) next;
                
                int opApply (int delegate(ref V value) dg)
                {
                        V   value;
                        int result;

                        while (next (value))
                               if ((result = dg(value)) != 0)
                                    break;
                        return result;
                }               
        }
        
        /***********************************************************************

                Iterator with no filtering

        ***********************************************************************/

        private struct Iterator
        {
                uint    row;
                Ref     cell,
                        prior;
                Ref[]   table;
                HashSet owner;
                uint    mutation;

                bool next (ref V v)
                {
                        while (cell is null)
                               if (row < table.length)
                                   cell = table [row++];
                               else
                                  return false;
  
                        prior = cell;
                        v = cell.value;
                        cell = cell.next;
                        return true;
                }

                void remove ()
                {
                        if (prior)
                            if (owner.remove (prior, row-1))
                                // ignore this change
                                ++mutation;
                        prior = null;
                }
                
                bool valid ()
                {
                        return owner.mutation is mutation;
                }
                
                Freach freach()
                {
                        Freach f = {&next};
                        return f;
                }
        }
}



/*******************************************************************************

*******************************************************************************/

debug (HashSet)
{
        import tango.io.Stdout;
        import tango.core.Thread;
        import tango.time.StopWatch;
       
        void main()
        {
                // usage examples ...
                auto set = new HashSet!(char[]);
                set.add ("foo");
                set.add ("bar");
                set.add ("wumpus");

                // implicit generic iteration
                foreach (value; set)
                         Stdout (value).newline;

                // explicit generic iteration
                foreach (value; set.iterator.freach)
                         Stdout (value).newline;

                // generic iteration with optional remove
                auto s = set.iterator;
                foreach (value; s.freach)
                        {} // s.remove;

                // incremental iteration, with optional remove
                char[] v;
                auto iterator = set.iterator;
                while (iterator.next(v))
                      {} //iterator.remove;
                
                // incremental iteration, with optional failfast
                auto it = set.iterator;
                while (it.valid && it.next(v))
                      {}

                // remove specific element
                set.remove ("wumpus");

                // remove first element ...
                while (set.take(v))
                       Stdout.formatln ("taking {}, {} left", v, set.size);
                
                
                // setup for benchmark, with a set of integers. We
                // use a chunk allocator, and presize the bucket[]
                auto test = new HashSet!(int, Container.hash, Container.reap, Container.Chunk);
                test.allocator.config (1000, 1000);
                test.buckets = 1_500_000;
                const count = 1_000_000;
                StopWatch w;

                // benchmark adding
                w.start;
                for (int i=count; i--;)
                     test.add(i);
                Stdout.formatln ("{} adds: {}/s", test.size, test.size/w.stop);

                // benchmark reading
                w.start;
                for (int i=count; i--;)
                     test.contains(i);
                Stdout.formatln ("{} lookups: {}/s", test.size, test.size/w.stop);

                // benchmark adding without allocation overhead
                test.clear;
                w.start;
                for (int i=count; i--;)
                     test.add(i);
                Stdout.formatln ("{} adds (after clear): {}/s", test.size, test.size/w.stop);

                // benchmark duplication
                w.start;
                auto dup = test.dup;
                Stdout.formatln ("{} element dup: {}/s", dup.size, dup.size/w.stop);

                // benchmark iteration
                w.start;
                foreach (value; test) {}
                Stdout.formatln ("{} element iteration: {}/s", test.size, test.size/w.stop);

                test.check;
        }
}

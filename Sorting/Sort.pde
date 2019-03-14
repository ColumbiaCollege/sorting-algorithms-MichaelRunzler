/**
 * Container-type class.
 * Contains access data from a call to a Callback<Integer>.
 */
class AccessEvent
{
  boolean readWrite;
  int index;
  int value;
  
  public AccessEvent(boolean readWrite, int index, int value){
    this.readWrite = readWrite;
    this.index = index;
    this.value = value;
  }
}

/**
 * Variable-radix cyclic LSD radix sort function.
 * This variant is a benchmarking version of the standard function - it routes all of its
 * array access calls (for the main input dataset, at least) through a CallbackArray wrapper,
 * thus allowing artificial slowdown of its progress and tracking of its access patterns.
 */
public static synchronized void benchmarkRadixSort(CallbackArray<Integer> array, int radix)
{
    // Total accesses/comparisons:
    //
    // Array reads: (n * significantDigits * 2) + n
    // Array writes: n * significantDigits
    // Comparisons: 0

    int[][] buckets = new int[radix][]; // Storage for each place's sorted numbers //<>//
    int maxMultiplier = 1; // # of sig. digits

    // Find maximum value in the input array
    // (n array reads, 0 comparisons)
    int max = Integer.MIN_VALUE;
    for(int i = 0; i < array.length; i++){
      int v = array.get(i);
      if(v > max) max = v;
    }

    // Find out how many significant digits that value has.
    // The sorter will stop sorting past that number of places.
    while(true){
        double mult = Math.pow(radix, maxMultiplier);
        if(Math.abs(max / mult) >= 1.0) maxMultiplier ++;
        else break;
    }

    // Main sorting algorithm: sort until the digit comparison pointer exceeds the number of significant
    // digits present in the largest value in the incoming array
    // ((n * significantDigits) * 2 array reads, n * significantDigits array writes, 0 comparisons)
    int multiplier = 1;
    do{
        if(multiplier > maxMultiplier) break;

        // Pre-size receptacle buckets for sorted values at this place by "pre-sorting" all values.
        // (n array reads, 0 comparisons)
        int factor = (int)Math.pow(radix, multiplier);
        int reductionFactor = (int)Math.pow(radix, multiplier - 1);
        int[] sizes = new int[buckets.length];
        for(int i = 0; i < array.length; i++) {
            int lsd = array.get(i) % factor;
            lsd /= reductionFactor;
            sizes[lsd]++;
        }

        // If all results are right-shifted so far as to be zero, we've run out of
        // spaces to check, break the check sequence.
        if(sizes[0] == array.length) break;

        // Size bucket array
        for(int i = 0; i < buckets.length; i++) buckets[i] = new int[sizes[i]];

        // Re-use bucket sizing array for index pointers
        sizes = new int[buckets.length];

        // Sort operation loop
        // (n array reads, 0 comparisons)
        for(int i = 0; i < array.length; i++)
        {
            int v = array.get(i);
            int lsd = v % factor;
            lsd /= reductionFactor;
            buckets[lsd][sizes[lsd]] = v;
            sizes[lsd] ++;
        }

        // Replace elements back into array in sorted order
        // (n array writes, 0 comparisons)
        int ptr = 0;
        for(int[] sub : buckets) {
            for(int i = 0; i < sub.length; i++){
                array.set(ptr + i, sub[i]);
            }
            
            ptr += sub.length;
        }

        multiplier ++;
    }while(true);
}

import processing.sound.*;
import java.util.Random;

public static final int ARRAY_SIZE = 250; // Size of the input dataset
public static final long ACCESS_DELAY_MS = 2; // Artificial delay time for each main array access
public static final int MAX_FREQUENCY = 1200; // Maximum frequency for sound output
public static final int MIN_FREQUENCY = 120; // Minimum frequency for sound output
public static final float TOP_BAR_SIZE = 40.0f; // Height of the top 'access counter' bar in pixels

color BG;
color READ;
color WRITE;
color IDLE;

float heightPerValue; // Height of each bar per integer value
float widthPerIndex; // Width of each bar per array index
float frequencyPerValue; // Output frequency (Hz) per integer value

int readCount;
int writeCount;

CallbackArray<Integer> workingSet; // Main working-set for the sorter function
ArrayList<AccessEvent> pending; // Access events that have occurred since the last call to draw()
boolean stackLock; // If true, any worker threads attempting to add events to the event queue will spinlock until this becomes false
TriOsc[] players; // Sound output oscillators
int soundSelector; // The last index of the player array that was used for sound output

/*
 * A short summary of how this works:
 * The main thread (the draw thread) doesn't do any of the actual sorting work here.
 * To track the array accesses, a daemon thread is started that does the actual sorting task.
 * The sorting engine is given a wrapped version of an array. This wrapped array fires off
 * an event (in the form of a call to a Callback object) every time a read or write operation
 * occurs. The call (still on the daemon thread) dumps a copy of its parameters (the index at which
 * the access occured, the value that was read/written, and the access type) to a 'stack' in the main
 * sketch class, then returns to its sorting work. The event-logging call is artificially delayed by a few
 * milliseconds, otherwise the sort would finish before any graphics or sound could be output.
 * Back on the main thread, the draw thread looks at the 'stack' of events every time it calls draw().
 * If there are any events on the stack, it locks the stack (causing any accesses by other threads to
 * stall until it is unlocked) and renders all of the changes to the screen. It clears the stack,
 * unlocks it, and returns to normal rendering. This results in a near-realtime rendering of what the
 * sorting code is doing, and tracking of how many accesses it performs over its lifetime.
 */

void setup()
{
  fullScreen();
  frameRate(30); // 30FPS provides more consistent sound output and better access rendering that 60FPS
  
  BG = color(0);
  READ = color(0, 0, 255);
  WRITE = color(255, 0, 0);
  IDLE = color(255);
  
  background(BG);
  stroke(BG);
  textSize(24);
  
  // Calculate dynamic sizing and output values
  heightPerValue = (height - TOP_BAR_SIZE) / (float)Integer.MAX_VALUE;
  widthPerIndex = width  / (float)ARRAY_SIZE;
  frequencyPerValue = (float)(MAX_FREQUENCY - MIN_FREQUENCY) / (float)Integer.MAX_VALUE;
  
  // Set up state flags and inputs
  readCount = 0;
  writeCount = 0;
  soundSelector = 0;
  pending = new ArrayList<AccessEvent>();
  stackLock = false;
  
  players = new TriOsc[10];
  for(int i = 0; i < players.length; i++){
    players[i] = new TriOsc(this);
    players[i].amp(0.5f);
  }
  
  // Set up access callback with artificial delay
  Callback<Integer> cb = new Callback<Integer>(){
    @Override
    public void access(boolean isWrite, int index, Integer value){
      try{ Thread.sleep(ACCESS_DELAY_MS); } catch(InterruptedException ignored) {}
      notifyAccess(isWrite, index, value == null ? 0 : value);
    }
  };
  
  // Generate input dataset: ARRAY_SIZE values between 0 and Integer.MAX_VALUE - 1 (inclusive)
  Integer[] input = new Integer[ARRAY_SIZE];
  Random rng = new Random(System.currentTimeMillis());
  for(int i = 0; i < ARRAY_SIZE; i++) input[i] = rng.nextInt(Integer.MAX_VALUE);
  
  // Initialize benchmarking array set
  workingSet = new CallbackArray(input, cb);
  
  // Set up worker daemon thread and run it
  Thread worker = new Thread(new Runnable(){
    @Override
    public void run(){
      benchmarkRadixSort(workingSet, 10);
      System.out.println("Completed dataset:\n");
      for(int i : workingSet.array) System.out.printf("%010d\n", i);
    }
  });
  
  worker.setDaemon(true);
  worker.start();
}

void draw()
{
  // Refresh image: blank background, then draw idle bars for all dataset entries
  background(BG);
  float x = 0;
  fill(IDLE);
  for(int i : workingSet.array){
    rect(x, height - heightPerValue * i, widthPerIndex, heightPerValue * i);
    x += widthPerIndex;
  }
  
  // Draw status message text
  fill(IDLE);
  stroke(IDLE);
  text(String.format("Radix Sort (LSD) - %d array reads, %d array writes, %.1f ms delay", readCount, writeCount, (float)ACCESS_DELAY_MS), 5, 5, width, TOP_BAR_SIZE);
  noStroke();
  
  // Lock event stack and draw all pending operations to their proper locations on the screen
  stackLock = true;
  for(AccessEvent event : pending)
  {
    fill(event.readWrite ? WRITE : READ);
    rect(widthPerIndex * event.index, height - heightPerValue * event.value, widthPerIndex, heightPerValue * event.value);
    if(event.readWrite) writeCount ++;
    else readCount ++;
  }
  
  // If the stack is empty (e.g we're done), stop all of the oscillator players
  if(pending.size() == 0)
    for(TriOsc player : players) player.stop();
  
  // Clear and unlock the event stack
  pending.clear();
  stackLock = false;
}

/**
 * Called by subthreads wishing to log an access event to the main thread.
 */
void notifyAccess(boolean readWrite, int index, int value)
{
  playSound(value);
  
  // Spinlock until the stack unlocks
  while(stackLocked()){
    try{ Thread.sleep(5); } catch(InterruptedException ignored){}
  }
  
  pending.add(new AccessEvent(readWrite, index, value));
}

boolean stackLocked(){
  return stackLock;
}

void playSound(int value)
{
  // Increment the selector counter; this ends up cycling through all of the players in order with
  // successive calls to this method
  soundSelector ++;
  if(soundSelector >= players.length) soundSelector = 0;
  
  // Set the frequency and play the sound
  players[soundSelector].freq((frequencyPerValue * value) + MIN_FREQUENCY);
  players[soundSelector].play();
}

/**
 * Variable-radix cyclic LSD radix sort function.
 * @param array the array to be sorted. Mutated by reference - non-mutable arrays should have a copy passed instead.
 * @param radix the radix to sort by. Leave at 10 if unsure of appropriate value.
 */
public static void radixSort(int[] array, int radix)
{
    // Total accesses/comparisons:
    //
    // Array reads: (n * significantDigits * 2) + n
    // Array writes: n * significantDigits
    // Comparisons: 0

    int[][] buckets = new int[radix][]; // Storage for each place's sorted numbers
    int maxMultiplier = 1; // # of sig. digits

    // Find maximum value in the input array
    // (n array reads, 0 comparisons)
    int max = Integer.MIN_VALUE;
    for(int i : array) if(i > max) max = i;

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
        for(int v : array) {
            int lsd = v % factor;
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
        for(int v : array)
        {
            int lsd = v % factor;
            lsd /= reductionFactor;
            buckets[lsd][sizes[lsd]] = v;
            sizes[lsd] ++;
        }

        // Replace elements back into array in sorted order
        // (n array writes, 0 comparisons)
        int ptr = 0;
        for(int[] sub : buckets) {
            System.arraycopy(sub, 0, array, ptr, sub.length);
            ptr += sub.length;
        }

        multiplier ++;
    }while(true);
}

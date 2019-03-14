
/**
 * Contains executable instructions to be executed when an array access event is detected.
 */
interface Callback<T>
{
  public void access(boolean isWrite, int index, T value);
}

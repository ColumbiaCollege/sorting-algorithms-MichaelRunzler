
/**
 * An array wrapper that behaves (for the most part) like a standard array, but
 * it logs an event to the provided Callback every time the wrapped array is read from
 * or written to.
 */
class CallbackArray<T>
{
  private T[] array;
  private Callback<T> notify;
  public int length;
  
  public CallbackArray(T[] array, Callback<T> onAccess)
  {
    this.array = array;
    this.length = array.length;
    this.notify = onAccess;
  }
  
  public T[] getAll()
  {
    for(int i = 0; i < array.length; i++) notify.access(false, i, array[i]);
    return array.clone();
  }
  
  public void setAll(T[] newValue)
  {
    for(int i = 0; i < array.length; i++) notify.access(true, i, i < newValue.length ? newValue[i] : null);
    this.array = newValue.clone();
    this.length = this.array.length;
  }
  
  public T get(int index){
    notify.access(false, index, array[index]);
    return array[index];
  }
  
  public void set(int index, T value)
  {
    notify.access(true, index, value);
    array[index] = value;
  }
  
  public void blank()
  {
    for(int i = 0; i < array.length; i++){
      notify.access(true, i, null);
      array[i] = null;
    }
  }
  
  public int length(){
    return array.length;
  }
}

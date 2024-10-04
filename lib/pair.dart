class Pair<T,L> { // Was it this hard google?
  T first;
  L second;
  Pair(this.first, this.second);
  
  @override
  String toString() {
    return 'Pair{first: $first, second: $second}';
  }
}
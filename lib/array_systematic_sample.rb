class Array
  def systematic_sample(n)
    return self if empty? or n >= size or n <= 0
    step = size / n
    i = 0
    result = []
    while i < size
      result.push(self[i])
      i += step
    end
    result.push(self.last) if result.size < n
    result
  end
end



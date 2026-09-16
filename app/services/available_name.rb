# A name that is free, starting from the one somebody would naturally give.
#
# Saving breakfast on two different days, or running the same split twice, is
# the ordinary case — so a prefilled name that collided would be a validation
# error on something the user never typed. Both places that prefill a name
# answer this the same way, and did so as two identical copies until one of
# them was going to be changed without the other.
#
# A name the user *does* type is never sent through here: it is theirs, and a
# collision is something to tell them about rather than to work around.
module AvailableName
  def self.for(base, taken:)
    return base unless taken.include?(base)

    (2..).each { |suffix| return "#{base} #{suffix}" unless taken.include?("#{base} #{suffix}") }
  end
end

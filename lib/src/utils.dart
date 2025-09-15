part of '../free_disposer.dart';

/// Blacklisted types that cannot have Finalizers attached
const Set<Type> _blacklistedTypes = {int, double, num, bool, String};

@pragma('vm:prefer-inline')
bool _isBlacklisted(Object? object) {
  if (object == null) return true;
  final type = object.runtimeType;
  return _blacklistedTypes.contains(type) ||
      object is Enum ||
      object is Symbol ||
      object is Type;
}

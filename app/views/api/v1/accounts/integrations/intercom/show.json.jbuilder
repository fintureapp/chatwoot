if @hook
  json.partial! 'api/v1/models/hook', formats: [:json], resource: @hook
else
  json.null!
end

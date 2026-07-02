class DataImports::Intercom::ContactsPageJob < DataImports::Intercom::BaseJob
  def perform(data_import, starting_after = nil)
    return if skip_import?(data_import)

    importer = importer_for(data_import)
    return if importer.contacts_completed?

    result = importer.import_contacts_page(starting_after: starting_after)
    return self.class.perform_later(data_import, result.next_cursor) unless result.done?

    enqueue_conversations_or_finish(data_import, importer)
  rescue StandardError => e
    fail_unexpected_error(importer, e)
  end

  private

  def enqueue_conversations_or_finish(data_import, importer)
    if importer.import_conversations? && !importer.conversations_completed?
      DataImports::Intercom::ConversationsPageJob.perform_later(data_import, importer.cursor_for('conversations'))
    else
      importer.finish!
    end
  end
end

Feature: Work items
  In order to coordinate work amongst downloaders
  Downloaders must be able to check out names of items.

  Scenario: Requesting a work item
    Given the tracker has the work items
      | item   |
      | abc123 |

    When I request a work item as "foobar"

    Then the response has status 200
    Then I receive a work item
    Then the tracker knows that "abc123" is claimed by "foobar"

  Scenario: When no work items are unclaimed
    When I request a work item as "foobar"

    Then the response has status 404

  Scenario: Marking a work item done
    Given the tracker has the work items
      | item   |
      | abc123 |
      | def456 |

    When downloader "foobar" marks item "abc123" done with 1024 bytes

    Then the response has status 200
    Then the tracker knows that "abc123" is done
     And the tracker knows that "foobar" has downloaded 1 item and 1024 bytes

  Scenario: When an ip is blocked
    Given the tracker has the work items
      | item   |
      | abc123 |

    Given ip 192.0.0.1 has been blocked

    When I request a work item as "foobar" from ip 192.0.0.1

    Then the response has status 200
    Then I receive a work item "abc123"
     But the tracker knows that "abc123" is not claimed


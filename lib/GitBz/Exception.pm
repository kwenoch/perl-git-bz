package GitBz::Exception;

# This file is part of git-bz.
#
# git-bz is free software; you can redistribute it and/or modify it
# under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 3 of the License, or
# (at your option) any later version.
#
# git-bz is distributed in the hope that it will be useful, but
# WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE. See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with git-bz; if not, see <https://www.gnu.org/licenses>.

use Modern::Perl;
use Exception::Class (
    'GitBz::Exception' => {
        description => 'Base GitBz exception',
    },
    'GitBz::Exception::Git' => {
        isa         => 'GitBz::Exception',
        description => 'Git operation failed',
    },
    'GitBz::Exception::Bugzilla' => {
        isa         => 'GitBz::Exception',
        description => 'Bugzilla API error',
    },
    'GitBz::Exception::Config' => {
        isa         => 'GitBz::Exception',
        description => 'Configuration error',
    },
    'GitBz::Exception::MethodNotImplemented' => {
        isa         => 'GitBz::Exception',
        description => 'Method not implemented',
        fields      => ['method'],
    },
);

1;

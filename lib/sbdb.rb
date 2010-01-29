require 'bdb'

module SBDB
	CREATE = Bdb::DB_CREATE
	AUTO_COMMIT = Bdb::DB_AUTO_COMMIT
	INIT_TXN = Bdb::DB_INIT_TXN
	INIT_LOCK = Bdb::DB_INIT_LOCK
	INIT_LOG = Bdb::DB_INIT_LOG
	INIT_MPOOL = Bdb::DB_INIT_MPOOL

	class Environment
		def bdb_object
			@env
		end

		def initialize dir, flags = nil, mode = nil
			flags ||= INIT_TXN | INIT_LOCK | INIT_LOG | INIT_MPOOL | CREATE
			mode ||= 0
			@env = Bdb::Env.new 0
			begin @env.open dir, flags, mode
			rescue Object
				close
				raise
			end

			return self  unless block_given?

			begin yield self
			ensure close
			end
			nil
		end

		def close
			@env.close
		end

		class << self
			alias open new
		end

		def open type, *p, &e
			p[5] = self
			type.new *p, &e
		end
		alias db open
		alias open_db open
	end
	Env = Environment

	class DB
		UNKNOWN = Bdb::Db::UNKNOWN
		BTREE = Bdb::Db::BTREE
		HASH = Bdb::Db::HASH
		QUEUE = Bdb::Db::QUEUE
		ARRAY = RECNO = Bdb::Db::RECNO

		attr_reader :home

		include Enumerable
		def bdb_object
			@db
		end

		class << self
			def new *p, &e
				x = super *p
				return x  unless e
				begin e.call x
				ensure
					x.sync
					x.close
				end
			end
			alias open new
		end

		def initialize file, name = nil, type = nil, flags = nil, mode = nil, txn = nil, env = nil
			flags ||= 0
			type ||= UNKNOWN
			type = BTREE  if type == UNKNOWN and (flags & CREATE) == CREATE
			mode ||= 0
			@home = env
			@db = env ? env.bdb_object.db : Bdb::Db.new
			begin @db.open txn, file, name, type, flags, mode
			rescue Object
				close
				raise $!
			end
		end

		def sync
			@db.sync
		end

		def close f = nil
			@db.close f || 0
		end

		def [] k
			@db.get nil, k, nil, 0
		end

		def []= k, v
			@db.put nil, k, v, 0
		end

		def cursor &e
			Cursor.new self, &e
		end

		def each k = nil, v = nil, &e
			cursor{|c|c.each k, v, &e}
		end

		def reverse k = nil, v = nil, &e
			cursor{|c|c.reverse k, v, &e}
		end

		def to_hash k = nil, v = nil
			h = {}
			each( k, v) {|k, v| h[ k] = v }
			h
		end
	end

	class Cursor
		NEXT = Bdb::DB_NEXT
		FIRST = Bdb::DB_FIRST
		LAST = Bdb::DB_LAST
		PREV = Bdb::DB_PREV
		SET = Bdb::DB_SET

		attr_reader :db

		include Enumerable
		def bdb_object
			@cursor
		end

		def self.new *p
			x = super *p
			return x  unless block_given?
			begin yield x
			ensure x.close
			end
		end

		def initialize ref
			obj = ref.bdb_object
			@cursor, @db = *if Cursor === ref
					[obj.dup, ref.db]
				else [obj.cursor( nil, 0), ref]
				end
		end

		def close
			@cursor.close
		end

		def get k, v, f
			@cursor.get k, v, f
		end

		def count
			@cursor.count
		end

		def reverse k = nil, v = nil, &e
			each k, v, LAST, PREV, &e
		end

		def each k = nil, v = nil, f = nil, n = nil
			return Enumerator.new( self, :each, k, v, f, n)  unless block_given?
			n ||= NEXT
			e = @cursor.get k, v, f || FIRST
			return  unless e
			yield *e
			yield *e  while e = @cursor.get( k, v, n)
			nil
		end

		def first k = nil, v = nil
			@cursor.get k, v, FIRST
		end

		def last k = nil, v = nil
			@cursor.get k, v, LAST
		end

		def next k = nil, v = nil
			@cursor.get k, v, NEXT
		end

		def prev k = nil, v = nil
			@cursor.get k, v, PREV
		end
	end

	class Unknown < DB
		def self.new *p, &e
			super *p[0...2], UNKNOWN, *p[2..-1], &e
		end
	end

	class Btree < DB
		def self.new *p, &e
			super *p[0...2], BTREE, *p[2..-1], &e
		end
	end

	class Hash < DB
		def self.new *p, &e
			super *p[0...2], HASH, *p[2..-1], &e
		end
	end

	class Recno < DB
		def self.new *p, &e
			super *p[0...2], RECNO, *p[2..-1], &e
		end

		def [] k
			super [k].pack('N')
		end

		def []= k, v
			super [k].pack('N'), v
		end
	end
	Array = Recno

	class Queue < DB
		def self.new *p, &e
			super *p[0...2], QUEUE, *p[2..-1], &e
		end

		def [] k
			super [k].pack('N')
		end

		def []= k, v
			super [k].pack('N'), v
		end
	end
end
require 'spec_helper'
require 'pry'
require 'user'

RSpec.describe Palette::ElasticSearch do

  it 'has a version number' do
    expect(Palette::ElasticSearch::VERSION).not_to be nil
  end

  describe 'json' do
    let(:attributes) do
      {
        name: 'Steve Jobs',
        name_prefix: 'Steve Jobs',
        age: 50,
        'phone_numbers.number': '+81 01-2345-6789',
        created_at: Date.parse('2018-1-1')
      }
    end

    let(:result) do
      {
        query: {
          bool: {
            must: [
              {
                bool: {
                  must: [
                   { simple_query_string: { query: "Steve", fields: [:name], analyzer: "ngram"} },
                   { simple_query_string: { query: "Jobs",  fields: [:name], analyzer: "ngram"} }
                  ]
                }
              },
              {
                bool: {
                  must: [
                    { match: { name_prefix: { query: "Steve Jobs", analyzer: "standard" } } }
                  ]
                }
              },
              {
                bool: {
                  must: [
                    { match: { age: { query: "50", analyzer: :keyword_analyzer } } }
                  ]
                }
              },
              {
                nested: {
                  path: "phone_numbers",
                  query: {
                    bool: {
                      must: [
                        { match: { "phone_numbers.number": { query: "+81 01-2345-6789", analyzer: :keyword_analyzer } } }
                      ]
                    }
                  }
                }
              },
              {
                range: {
                  created_at: {
                    gte: Time.parse("2018-01-01 00:00:00.000000000 +0900"),
                    lte: Time.parse("2018-01-01 23:59:59.999999999 +0900")
                  }
                }
              }
            ],
            filter: {}
          }
        }
      }
    end

    subject do
      ::Palette::ElasticSearch::QueryFactory.build([User], attributes)
    end

    it 'jsonが一致すること' do
      expect(subject).to eq result
    end
  end

  shared_examples_for 'AND query is generated as much as the number of attributes' do
    it do
      res = ::Palette::ElasticSearch::QueryFactory.build([User], attributes)
      expect(res[:query][:bool][:must].size).to eq(attributes.keys.size)
    end
  end

  describe 'build' do
    let(:attributes) {
      {
        name: 'Steve Jobs',
        name_prefix: 'Steve Jobs',
        age: 50,
        'phone_numbers.number': '+81 01-2345-6789',
        created_at: Date.today
      }
    }
    it_behaves_like 'AND query is generated as much as the number of attributes'
  end

  describe 'check date search query parameter' do
    let(:created_at) { nil }
    let(:attributes) {
      {
        name: 'Steve Jobs',
        name_prefix: 'Steve Jobs',
        age: 50,
        'phone_numbers.number': '+81 01-2345-6789',
        created_at: created_at
      }
    }
    context 'Hash object' do
      context 'only gte' do
        let(:created_at) { { gte: Date.yesterday } }
        it_behaves_like 'AND query is generated as much as the number of attributes'
      end
      context 'only lte' do
        let(:created_at) { { lte: Date.tomorrow } }
        it_behaves_like 'AND query is generated as much as the number of attributes'
      end
      context 'both gte and lte' do
        let(:created_at) { { "gte" => Date.yesterday, "lte" => Date.tomorrow } }
        it_behaves_like 'AND query is generated as much as the number of attributes'
      end
      context 'neither gte and lte' do
        let(:created_at) { { gte: nil, lte: nil } }
        it_behaves_like 'AND query is generated as much as the number of attributes'
      end
    end

    context 'Range object' do
      let(:created_at) { Date.yesterday..Date.today }
      it_behaves_like 'AND query is generated as much as the number of attributes'
    end

    context 'Date object' do
      let(:created_at) { Date.today }
      it_behaves_like 'AND query is generated as much as the number of attributes'
    end
  end

  describe 'test query_partial_for' do

    let(:query) { nil }
    let(:fields) { nil }

    context 'query dose not have a space' do
      let(:query) { 'Steve' }
      let(:field) { 'name' }
      it 'single AND query is generated' do
        res = ::Palette::ElasticSearch::QueryFactory.send(:query_partial_for, query, field)
        expect(res[:bool][:must].size == 1).to eq(true)
      end
    end

    context 'query has a space' do
      let(:query) { 'Steve Jobs' }
      let(:field) { 'name' }
      it 'multiple AND query is generated' do
        res = ::Palette::ElasticSearch::QueryFactory.send(:query_partial_for, query, field)
        expect(res[:bool][:must].size > 1).to eq(true)
      end
    end
  end

  describe 'test nested_for' do
    let(:query) { '+81 01-2345-6789' }
    let(:field) { 'phone_numbers.number' }
    before do
      ::Palette::ElasticSearch::QueryFactory.send(:set_mappings_hashes, [User])
    end
    it 'nested query is generated' do
      res = ::Palette::ElasticSearch::QueryFactory.send(:nested_for, query, field)
      expect(res[:nested].present?).to eq(true)
      expect(res[:nested][:path].to_s).to eq(field.to_s.split('.').first.to_s)
    end
  end

  describe 'get_query_pattern' do
    before do
      ::Palette::ElasticSearch::QueryFactory.send(:set_mappings_hashes, [User])
    end

    context 'type is nested' do
      let(:field) { 'phone_numbers.number'.to_sym }
      it 'nested is returned' do
        res = ::Palette::ElasticSearch::QueryFactory.send(:get_query_pattern, field)
        expect(res[:pattern]).to eq('nested')
      end
    end

    context 'type is date' do
      let(:field) { :created_at }
      it 'date is returned' do
        res = ::Palette::ElasticSearch::QueryFactory.send(:get_query_pattern, field)
        expect(res[:pattern]).to eq('date')
      end
    end

    context 'partial' do
      let(:field) { :name }
      it 'partial_match is returned' do
        res = ::Palette::ElasticSearch::QueryFactory.send(:get_query_pattern, field)
        expect(res[:pattern]).to eq('partial_match')
      end
    end

    context 'full_match' do
      let(:field) { :age }
      it 'full_match is returned' do
        res = ::Palette::ElasticSearch::QueryFactory.send(:get_query_pattern, field)
        expect(res[:pattern]).to eq('full_match_with_analyzer')
      end
    end

    context 'prefix_match' do
      let(:field) { :name_prefix }
      it 'prefix_match is returned' do
        res = ::Palette::ElasticSearch::QueryFactory.send(:get_query_pattern, field)
        expect(res[:pattern]).to eq('prefix_match')
      end
    end
  end
end

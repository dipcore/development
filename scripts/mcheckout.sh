if [ "$1" == "" ]; then
    echo "usage: mcheckout TAG"
    exit 0
fi
echo checkout tag $1

repo forall -p -c "
if git rev-parse $1 >/dev/null 2>&1
then
git checkout $1 -b $1
else
git checkout -b $1-null
git rm -r *
fi" | cat
